;;;; telnet/connection.lisp — Telnet connection handler using flexi-streams
;;;;
;;;; Provides a maximally portable telnet connection that:
;;;;   1. Extracts the native socket FD from the usocket wrapper
;;;;   2. Creates a binary stream for byte-level I/O
;;;;   3. Implements RFC 854 telnet protocol processing (IAC escaping,
;;;;      option negotiation, subnegotiation)
;;;;   4. Uses flexi-streams for UTF-8 ↔ bytes encoding
;;;;
;;;; Architecture:
;;;;   Application (character I/O)
;;;;        ↑ ↓
;;;;   flexi-streams (string-to-octets / octets-to-string)
;;;;        ↑ ↓
;;;;   Telnet IAC processor (escape/unescape, command handling)
;;;;        ↑ ↓
;;;;   Binary stream (from socket FD)
;;;;
;;;; The binary stream is created directly from the socket FD so we
;;;; have full control over byte-level I/O.  The usocket's character
;;;; stream is never used — we keep the usocket only for wait-for-input
;;;; and socket-close.  This avoids the SBCL-internals hack in the old
;;;; session-keepalive (which wrote raw bytes through sb-unix:unix-write).

(in-package #:telnet)

;;; ----------------------------------------------------------------
;;; Platform-specific: get native file descriptor from usocket
;;; ----------------------------------------------------------------

(defun %socket-fd (usocket)
  "Extract the native OS file descriptor from a usocket."
  #+sbcl
  (let ((native (usocket:socket usocket)))
    (when (typep native 'sb-bsd-sockets:socket)
      (sb-bsd-sockets:socket-file-descriptor native)))
  #+ccl
  (ccl:stream-device (usocket:socket-stream usocket) :input)
  #+ecl
  (let ((stream (usocket:socket-stream usocket)))
    (when stream
      (ext:stream-fd stream)))
  #-(or sbcl ccl ecl)
  (error "telnet: unsupported Lisp implementation. Please port %socket-fd."))

;;; ----------------------------------------------------------------
;;; Open a binary stream on a socket FD
;;; ----------------------------------------------------------------

(defun %make-binary-fd-stream (fd &key (input t) (output t))
  "Create a binary (unsigned-byte 8) stream on the given file descriptor for
the requested direction(s).  The stream does NO character encoding — byte
I/O is direct."
  #+sbcl
  (sb-sys:make-fd-stream fd
                          :input input :output output
                          :element-type '(unsigned-byte 8)
                          :buffering :full
                          :name "telnet-binary-stream")
  #+ccl
  (ccl:make-fd-stream fd :direction (cond ((and input output) :io)
                                          (input :input)
                                          (t :output))
                       :element-type '(unsigned-byte 8))
  #+ecl
  (ext:make-stream-from-fd fd :direction (cond ((and input output) :io)
                                               (input :input)
                                               (t :output))
                           :element-type '(unsigned-byte 8))
  #-(or sbcl ccl ecl)
  (error "telnet: unsupported Lisp implementation."))

;;; ----------------------------------------------------------------
;;; Telnet connection class
;;; ----------------------------------------------------------------

(defclass telnet-connection ()
  ((usocket
    :initarg :usocket
    :reader telnet-conn-usocket
    :documentation "The usocket (for wait-for-input and close).")
   (raw-stream
    :initarg :raw-stream
    :reader telnet-conn-raw-stream
    :documentation "Binary (unsigned-byte 8) INPUT stream from the socket.
All reads go through this stream.  When OUT-STREAM is NIL (the usual
case for a bidirectional TCP socket), writes also go through this
stream.  Telnet protocol commands are read/written directly.
Application data is encoded/decoded via flexi-streams:string-to-octets
and octets-to-string.")
   (out-stream
    :initarg :out-stream
    :initform nil
    :reader telnet-conn-out-stream-slot
    :documentation "Optional separate binary OUTPUT stream.  When NIL,
writes fall back to RAW-STREAM (the normal full-duplex socket case).
A distinct output stream is useful when the underlying transport is
half-duplex (e.g. a pair of unix pipes), where the read and write
endpoints are different streams.")
   (protocol
    :initarg :protocol
    :reader telnet-conn-protocol
    :documentation "The telnet-protocol instance managing option state.")
   (lock
    :initform (bordeaux-threads:make-lock "telnet-connection-lock")
    :reader telnet-conn-lock
    :documentation "Lock serialising access to the connection's I/O.")
   (alive-p
    :initform t
    :accessor telnet-connection-alive-p
    :documentation "NIL when the connection has been closed or lost.")
   ;; Read-side state
   (read-buffer
    :initform (make-array 256 :element-type '(unsigned-byte 8)
                                :adjustable t :fill-pointer 0)
    :documentation "Scratch buffer used by %READ-BYTE-INTO when reading
the bytes of a telnet command (IAC ...).")
   (utf8-pending
    :initform (make-array 4 :element-type '(unsigned-byte 8)
                            :adjustable t :fill-pointer 0)
    :documentation "Holds the bytes of an incomplete UTF-8 sequence
between calls, so that a multi-byte character split across several
reads is decoded correctly once all its bytes have arrived.")
   (line-buffer
    :initform (make-array 256 :element-type 'character
                               :adjustable t :fill-pointer 0)
    :documentation "Characters accumulated for the current line being read."))
  (:documentation "A telnet connection wrapping a raw TCP socket.

Provides:
- RFC 854 option negotiation
- IAC command processing (NOP keepalives, etc.)
- UTF-8 character encoding/decoding via flexi-streams
- Thread-safe read and write operations"))

;;; ----------------------------------------------------------------
;;; Effective output stream
;;; ----------------------------------------------------------------

(defun telnet-conn-out-stream (conn)
  "Return the stream to which outgoing bytes should be written.

Uses the dedicated OUT-STREAM slot when present (half-duplex transports
such as a pair of pipes); otherwise falls back to RAW-STREAM (the normal
full-duplex socket case where the same stream is read and written)."
  (or (telnet-conn-out-stream-slot conn)
      (telnet-conn-raw-stream conn)))

;;; ----------------------------------------------------------------
;;; Construction
;;; ----------------------------------------------------------------

(defun make-telnet-connection (usocket)
  "Create a new telnet-connection from a usocket.

Duplicates the socket FD to create a dedicated binary stream, keeping
the usocket's character stream open only for compatibility (it is
never read from).  Performs initial RFC 854 option negotiation.

USOCKET must be a usocket:stream-usocket from usocket:socket-accept
or usocket:socket-connect."
  (let* ((fd (%socket-fd usocket))
         ;; Use SEPARATE input and output streams, each on its own dup'd
         ;; file descriptor.  Two reasons:
         ;;   1. A single bidirectional fd-stream is unreliable on SBCL —
         ;;      issuing a write + FORCE-OUTPUT and then reading on the same
         ;;      fd-stream can corrupt the input side and stall subsequent
         ;;      reads.  Telnet constantly interleaves reads (incoming data)
         ;;      with writes (negotiation responses), so this bug bites hard.
         ;;   2. Dup'ing also prevents the usocket character stream from
         ;;      stealing bytes from the shared socket receive queue.
         (in-stream  (%make-binary-fd-stream (sb-posix:dup fd) :input t :output nil))
         (out-stream (%make-binary-fd-stream (sb-posix:dup fd) :input nil :output t))
         (protocol (make-instance 'telnet-protocol))
         (conn (make-instance 'telnet-connection
                              :usocket usocket
                              :raw-stream in-stream
                              :out-stream out-stream
                              :protocol protocol)))
    ;; Perform initial option negotiation
    (let ((out-stream (telnet-conn-out-stream conn))
          (init-cmds (telnet-init-negotiation protocol)))
      (dolist (cmd init-cmds)
        (handler-case
            (write-sequence cmd out-stream)
          (stream-error (e)
            (declare (ignore e))
            (setf (telnet-connection-alive-p conn) nil)
            (return-from make-telnet-connection conn))))
      (force-output out-stream))
    conn))

;;; ----------------------------------------------------------------
;;; Internal: Input readiness (data-available OR end-of-file)
;;; ----------------------------------------------------------------

(defun %input-ready-p (stream timeout-seconds)
  "Return true when STREAM can be read without blocking within
TIMEOUT-SECONDS — that is, when application data is buffered/available OR
the stream is at end-of-file.  Returns NIL on timeout.

We POLL rather than issue a single blocking wait, because incoming data
commonly arrives in several TCP segments (especially during option
negotiation): a one-shot wait can miss bytes that land just after the
first check.  Each iteration:

  * LISTEN covers data already sitting in the stream's input buffer.
  * On SBCL a non-blocking readiness probe on the underlying file
    descriptor covers data that has reached the kernel but not yet the
    stream buffer, AND end-of-file — LISTEN returns NIL at EOF, so the
    fd-level probe is what lets a closed peer be observed promptly
    (a subsequent READ-BYTE then returns :EOF)."
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout-seconds internal-time-units-per-second))))
    (loop
      (when (listen stream) (return t))
      #+sbcl
      (when (sb-sys:wait-until-fd-usable (sb-sys:fd-stream-fd stream) :input 0)
        (return t))
      (when (>= (get-internal-real-time) deadline) (return nil))
      (sleep 0.02))))

;;; ----------------------------------------------------------------
;;; Internal: Read a single byte, handling errors
;;; ----------------------------------------------------------------

(defun %read-byte-into (stream buffer pos)
  "Read one byte from STREAM and store it at POS in BUFFER.
Returns the byte value, or :eof if the stream is exhausted."
  (handler-case
      (let ((b (read-byte stream nil :eof)))
        (if (eq b :eof)
            :eof
            (progn
              (setf (aref buffer pos) b)
              b)))
    (stream-error (e)
      (declare (ignore e))
      :eof)
    (error (e)
      (error 'telnet-connection-lost
             :message (format nil "Read error: ~A" e)))))

;;; ----------------------------------------------------------------
;;; Internal: Process incoming bytes through the telnet state machine
;;; ----------------------------------------------------------------

(defun %process-incoming-byte (conn byte)
  "Process a single incoming byte.

Returns one of:
  :command           — byte was consumed as part of a telnet command
  :data              — byte is application data (stored in read-buffer)
  :subneg-incomplete — byte consumed, subnegotiation still in progress

Side-effects: may write negotiation responses to the output stream."
  (let ((protocol (telnet-conn-protocol conn))
        (raw-stream (telnet-conn-out-stream conn)))
    (cond
      ;; Inside subnegotiation
      ((telnet-in-subneg-p protocol)
       (let ((buf (telnet-subneg-buffer protocol)))
         (cond
           ;; IAC SE — end subnegotiation
           ((and (> (fill-pointer buf) 0)
                 (= (aref buf (1- (fill-pointer buf))) iac)
                 (= byte se))
            (decf (fill-pointer buf))
            (let ((option (aref buf 0))
                  (data (make-array (- (fill-pointer buf) 1)
                                    :element-type '(unsigned-byte 8))))
              (when (> (length data) 0)
                (replace data buf :start2 1))
              (setf (fill-pointer buf) 0)
              (setf (telnet-in-subneg-p protocol) nil)
              (let ((responses (telnet-process-subnegotiation protocol option data)))
                (dolist (resp responses)
                  (handler-case (write-sequence resp raw-stream)
                    (error () nil)))
                (when responses (force-output raw-stream)))))
           ;; IAC IAC inside subneg — literal 255
           ((and (> (fill-pointer buf) 0)
                 (= (aref buf (1- (fill-pointer buf))) iac)
                 (= byte iac))
            (vector-push-extend byte buf))
           (t
            (vector-push-extend byte buf)))
         :subneg-incomplete))

      ;; Outside subnegotiation, IAC received
      ((= byte iac)
       :iac-pending)

      ;; Regular data byte — accumulate
      (t
       (vector-push-extend byte (slot-value conn 'read-buffer))
       :data))))

;;; ----------------------------------------------------------------
;;; Internal: Handle a telnet command (called after IAC + command-byte)
;;; ----------------------------------------------------------------

(defun %handle-telnet-command (conn command option)
  "Process a telnet command (IAC COMMAND [OPTION]).
Writes any negotiation responses to the output stream."
  (let ((protocol (telnet-conn-protocol conn))
        (raw-stream (telnet-conn-out-stream conn)))
    (cond
      ((= command sb)
       (setf (telnet-in-subneg-p protocol) t)
       (setf (fill-pointer (telnet-subneg-buffer protocol)) 0))
      ((= command nop) nil)
      ((= command dm) nil)
      ((or (= command will) (= command wont) (= command do) (= command dont))
       (let ((responses (telnet-process-command protocol command option)))
         (dolist (resp responses)
           (handler-case (write-sequence resp raw-stream)
             (error () nil)))
         (when responses (force-output raw-stream))))
      (t nil))))

;;; ----------------------------------------------------------------
;;; Internal: Incremental UTF-8 decoder
;;; ----------------------------------------------------------------
;;;
;;; Telnet delivers application data one byte at a time, interleaved with
;;; IAC command sequences.  A multi-byte UTF-8 character may therefore be
;;; split across several reads.  We accumulate the bytes of an incomplete
;;; sequence in the connection's UTF8-PENDING buffer and only emit a
;;; character once a full sequence is available.
;;;
;;; Bytes that cannot form a valid UTF-8 sequence (e.g. a lone 0xFF, which
;;; is what IAC IAC unescapes to, or any invalid/overlong/surrogate
;;; encoding) are passed through as Latin-1 code points.  This guarantees
;;; that no byte is ever lost and that binary / non-UTF-8 data degrades
;;; gracefully rather than raising an error.

(defun %vector-shift-left (vec n)
  "Drop the first N elements of fill-pointer VECTOR in place."
  (let ((len (fill-pointer vec)))
    (when (> n 0)
      (replace vec vec :start2 n :end2 len)
      (setf (fill-pointer vec) (- len n)))))

(defun %utf8-sequence-length (lead-byte)
  "Return the total length (1-4) of the UTF-8 sequence beginning with
LEAD-BYTE, or :INVALID if LEAD-BYTE cannot start a sequence."
  (cond
    ((< lead-byte #x80) 1)
    ((<= #xC2 lead-byte #xDF) 2)   ; #xC0/#xC1 would be overlong -> invalid
    ((<= #xE0 lead-byte #xEF) 3)
    ((<= #xF0 lead-byte #xF4) 4)   ; > #xF4 is out of Unicode range
    (t :invalid)))

(defun %valid-codepoint-p (cp n)
  "Return true if codepoint CP is a valid, minimally-encoded scalar value
for an N-byte UTF-8 sequence (rejects overlong forms, UTF-16 surrogates,
and values beyond #x10FFFF)."
  (and (<= cp #x10FFFF)
       (not (<= #xD800 cp #xDFFF))
       (ecase n
         (2 (>= cp #x80))
         (3 (>= cp #x800))
         (4 (>= cp #x10000)))))

(defun %emit-data-byte (conn byte)
  "Feed one application data BYTE through the incremental UTF-8 decoder,
appending any completed characters to the connection's line buffer.

Invalid leading/continuation bytes are emitted as Latin-1 code points so
that no data is lost.  Returns no useful value."
  (let ((pending (slot-value conn 'utf8-pending))
        (line (slot-value conn 'line-buffer)))
    (vector-push-extend byte pending)
    (loop
      (when (zerop (fill-pointer pending))
        (return))
      (let* ((b0 (aref pending 0))
             (n (%utf8-sequence-length b0)))
        (cond
          ;; ASCII fast path.
          ((eql n 1)
           (vector-push-extend (code-char b0) line)
           (%vector-shift-left pending 1))

          ;; Invalid leading byte (continuation byte, 0xC0/0xC1, 0xF5-0xFF):
          ;; pass through as Latin-1 and drop a single byte.
          ((eq n :invalid)
           (vector-push-extend (code-char b0) line)
           (%vector-shift-left pending 1))

          ;; Incomplete multi-byte sequence: wait for the remaining bytes.
          ((< (fill-pointer pending) n)
           (return))

          ;; A complete candidate sequence: validate the continuation bytes.
          (t
           (let ((cp (logand b0 (ecase n (2 #x1F) (3 #x0F) (4 #x07))))
                 (valid t))
             (loop for i from 1 below n
                   for bi = (aref pending i)
                   do (if (<= #x80 bi #xBF)
                          (setf cp (logior (ash cp 6) (logand bi #x3F)))
                          (progn (setf valid nil) (return))))
             (cond
               ((and valid (%valid-codepoint-p cp n))
                (vector-push-extend (code-char cp) line)
                (%vector-shift-left pending n))
               (t
                ;; Malformed sequence: emit the leader as Latin-1, drop one
                ;; byte, and reprocess whatever remains.
                (vector-push-extend (code-char b0) line)
                (%vector-shift-left pending 1))))))))
    (values)))

(defun telnet-read-char (conn &key (timeout 300))
  "Read a single character from the telnet connection.

TIMEOUT is in seconds (can be fractional).  If no data arrives within
TIMEOUT seconds, returns (values nil :timeout).

Returns (values char nil) on success.
Returns (values nil :eof) when the connection is closed.
Returns (values nil :connection-lost) on fatal error."
  (let ((line (slot-value conn 'line-buffer)))
    ;; Return buffered characters first
    (when (> (fill-pointer line) 0)
      (let ((c (aref line 0)))
        (replace line line :start2 1 :end2 (fill-pointer line))
        (decf (fill-pointer line))
        (return-from telnet-read-char (values c nil))))

    ;; Wait until the stream is readable (data available OR EOF).  We do
    ;; not use usocket:wait-for-input because the usocket character stream
    ;; would steal bytes from the kernel buffer ahead of our binary stream.
    (unless (%input-ready-p (telnet-conn-raw-stream conn) timeout)
      (return-from telnet-read-char (values nil :timeout)))

    ;; Read and process bytes from the raw binary stream
    (let* ((raw-stream (telnet-conn-raw-stream conn))
           (buf (slot-value conn 'read-buffer)))
      (setf (fill-pointer buf) 0)

      (let ((b (%read-byte-into raw-stream buf 0)))
        (when (eq b :eof)
          (setf (telnet-connection-alive-p conn) nil)
          (return-from telnet-read-char (values nil :eof)))

        (if (= b iac)
            ;; IAC — telnet command
            (let ((cmd (%read-byte-into raw-stream buf 1)))
              (when (eq cmd :eof)
                (setf (telnet-connection-alive-p conn) nil)
                (return-from telnet-read-char (values nil :eof)))

              (cond
                ;; IAC IAC — literal 255 data byte
                ((= cmd iac)
                 (%emit-data-byte conn iac))

                ;; IAC SB — enter subnegotiation
                ((= cmd sb)
                 (setf (telnet-in-subneg-p (telnet-conn-protocol conn)) t)
                 (setf (fill-pointer (telnet-subneg-buffer (telnet-conn-protocol conn))) 0)
                 (loop
                   (let ((sbb (%read-byte-into raw-stream buf 0)))
                     (when (eq sbb :eof)
                       (setf (telnet-connection-alive-p conn) nil)
                       (return-from telnet-read-char (values nil :eof)))
                     (%process-incoming-byte conn sbb)
                     (when (not (telnet-in-subneg-p (telnet-conn-protocol conn)))
                       (return)))))

                ;; WILL/WONT/DO/DONT — 3-byte negotiation
                ((or (= cmd will) (= cmd wont) (= cmd do) (= cmd dont))
                 (let ((opt (%read-byte-into raw-stream buf 2)))
                   (when (eq opt :eof)
                     (setf (telnet-connection-alive-p conn) nil)
                     (return-from telnet-read-char (values nil :eof)))
                   (%handle-telnet-command conn cmd opt)))

                ;; Other 2-byte commands
                (t
                 (%handle-telnet-command conn cmd 0))))

            ;; Not IAC — application data byte, feed the UTF-8 decoder
            (%emit-data-byte conn b)))

      ;; Try to return a character from the line buffer
      (when (> (fill-pointer line) 0)
        (let ((c (aref line 0)))
          (replace line line :start2 1 :end2 (fill-pointer line))
          (decf (fill-pointer line))
          (return-from telnet-read-char (values c nil))))

      ;; No character yet — data was consumed by protocol processing
      (values nil :timeout))))

;;; ----------------------------------------------------------------
;;; Public: Read a line of text
;;; ----------------------------------------------------------------

(defun telnet-read-line (conn &key (timeout 300) (poll-interval 0.1))
  "Read a line of text from the telnet connection.

TIMEOUT is the total maximum time to wait in seconds.
POLL-INTERVAL is the granularity of polling in seconds.

Returns (values line nil) on success, where LINE is a string
without the trailing newline.
Returns (values nil :timeout) on timeout.
Returns (values nil :eof) when the connection is closed.
Returns (values nil :connection-lost) on error.

NOTE: This function accumulates characters in a LOCAL buffer.  It must
NOT reuse the connection's LINE-BUFFER slot, because TELNET-READ-CHAR
uses that slot internally to hold decoded-but-not-yet-returned
characters; sharing it would make TELNET-READ-CHAR re-read characters
this function has already consumed, looping forever until timeout."
  (let* ((deadline (+ (get-internal-real-time)
                      (* timeout internal-time-units-per-second)))
         (acc (make-array 64 :element-type 'character
                             :adjustable t :fill-pointer 0))
         (nul (code-char 0))
         (saw-cr nil))
    (loop
      (let ((remaining (- deadline (get-internal-real-time))))
        (when (<= remaining 0)
          (return (values nil :timeout)))

        (multiple-value-bind (char status)
            (telnet-read-char conn
                              :timeout (min poll-interval
                                            (/ remaining
                                               internal-time-units-per-second)))
          (cond
            ((and (null char) (eq status :timeout)) nil)

            ((and (null char) (or (eq status :eof) (eq status :connection-lost)))
             (return (values nil status)))

            ((char= char #\Return)
             (setf saw-cr t))

            ((and saw-cr (char= char #\Newline))
             (return (values (coerce acc 'string) nil)))

            ((and saw-cr (char= char nul))
             (return (values (coerce acc 'string) nil)))

            ((char= char #\Newline)
             (return (values (coerce acc 'string) nil)))

            (saw-cr
             (setf saw-cr nil)
             (vector-push-extend #\Return acc)
             (vector-push-extend char acc))

            (t
             (vector-push-extend char acc))))))))

;;; ----------------------------------------------------------------
;;; Public: Write a string
;;; ----------------------------------------------------------------

(defun telnet-write-string (conn string &key (end :crlf))
  "Write STRING to the telnet connection.

END controls line ending translation:
  :CRLF — append CR LF (default, RFC 854 NVT standard)
  :CR   — append CR only
  :LF   — append LF only
  NIL   — no line ending appended

IAC bytes (255) in the output are automatically escaped as IAC IAC."
  (unless (telnet-connection-alive-p conn)
    (error 'telnet-connection-lost :message "Connection is closed"))

  (bordeaux-threads:with-lock-held ((telnet-conn-lock conn))
    (let* ((raw-stream (telnet-conn-out-stream conn))
           (octets (flexi-streams:string-to-octets string :external-format :utf-8))
           (ending (ecase end
                     (:crlf #(13 10))
                     (:cr   #(13))
                     (:lf   #(10))
                     ((nil) #()))))
      (handler-case
          (progn
            ;; Write string bytes with IAC escaping
            (loop for b across octets do
              (write-byte b raw-stream)
              (when (= b iac)
                (write-byte iac raw-stream)))
            ;; Write ending
            (loop for b across ending do
              (write-byte b raw-stream))
            (force-output raw-stream))
        (stream-error (e)
          (declare (ignore e))
          (setf (telnet-connection-alive-p conn) nil)
          (error 'telnet-connection-lost :message "Write failed"))
        (error (e)
          (setf (telnet-connection-alive-p conn) nil)
          (error 'telnet-connection-lost
                 :message (format nil "Write error: ~A" e))))))
  nil)

;;; ----------------------------------------------------------------
;;; Public: Write raw bytes (for protocol commands)
;;; ----------------------------------------------------------------

(defun telnet-write-raw (conn byte-vector)
  "Write raw bytes to the connection without IAC escaping.
Useful for sending protocol commands."
  (unless (telnet-connection-alive-p conn)
    (error 'telnet-connection-lost :message "Connection is closed"))

  (bordeaux-threads:with-lock-held ((telnet-conn-lock conn))
    (handler-case
        (let ((out-stream (telnet-conn-out-stream conn)))
          (write-sequence byte-vector out-stream)
          (force-output out-stream))
      (stream-error (e)
        (declare (ignore e))
        (setf (telnet-connection-alive-p conn) nil)
        (error 'telnet-connection-lost :message "Write failed"))
      (error (e)
        (setf (telnet-connection-alive-p conn) nil)
        (error 'telnet-connection-lost
               :message (format nil "Write error: ~A" e))))))

;;; ----------------------------------------------------------------
;;; Public: Send a NOP keepalive
;;; ----------------------------------------------------------------

(defun telnet-send-nop (conn)
  "Send a Telnet NOP (No Operation) command (RFC 854 keepalive)."
  (handler-case
      (telnet-write-raw conn (make-command-1 nop))
    (telnet-connection-lost () nil)
    (telnet-error () nil)))

;;; ----------------------------------------------------------------
;;; Public: Close the connection
;;; ----------------------------------------------------------------

(defun telnet-connection-close (conn)
  "Close the telnet connection gracefully."
  (when (telnet-connection-alive-p conn)
    (setf (telnet-connection-alive-p conn) nil)
    (handler-case
        (progn
          ;; Close the binary stream(s) first
          (when (telnet-conn-raw-stream conn)
            (close (telnet-conn-raw-stream conn)))
          ;; Close a distinct output stream, if any
          (let ((out (telnet-conn-out-stream-slot conn)))
            (when (and out (not (eq out (telnet-conn-raw-stream conn))))
              (close out)))
          ;; Then close the usocket
          (when (telnet-conn-usocket conn)
            (usocket:socket-close (telnet-conn-usocket conn))))
      (error () nil)))
  nil)

;;; ----------------------------------------------------------------
;;; Public: Stream access
;;; ----------------------------------------------------------------

(defun telnet-connection-input-stream (conn)
  "Returns NIL — telnet connections do not expose raw CL streams.
Use telnet-read-line or telnet-read-char instead."
  (declare (ignore conn))
  nil)

(defun telnet-connection-output-stream (conn)
  "Returns NIL — telnet connections do not expose raw CL streams.
Use telnet-write-string instead."
  (declare (ignore conn))
  nil)
