;;;; telnet/connection.lisp — Telnet connection handler using flexi-streams
;;;;
;;;; Provides a maximally portable telnet connection that:
;;;;   1. Extracts the native socket FD from the usocket wrapper
;;;;   2. Creates a binary stream for byte-level I/O
;;;;   3. Implements RFC 854 telnet protocol processing (IAC escaping,
;;;;      option negotiation, subnegotiation)
;;;;   4. Exposes clean character-stream interfaces for the application layer
;;;;
;;;; The design avoids SBCL internals for keepalive by using flexi-streams
;;;; for the binary/character encoding boundary and usocket for all socket
;;;; operations.  The only platform-specific code is in %socket-fd and
;;;; %make-binary-fd-stream, which are isolated and trivial to port.
;;;;
;;;; Architecture:
;;;;   Application (character I/O)
;;;;        ↑ ↓
;;;;   flexi-stream (UTF-8 ↔ bytes)
;;;;        ↑ ↓
;;;;   Telnet IAC processor (escape/unescape, command handling)
;;;;        ↑ ↓
;;;;   Binary stream (from socket FD)
;;;;
;;;; Inspired by busybox telnetd's clean separation of protocol and I/O.

(in-package #:telnet)

;;; ----------------------------------------------------------------
;;; Platform-specific: get native file descriptor from usocket
;;; ----------------------------------------------------------------

(defun %socket-fd (usocket)
  "Extract the native OS file descriptor from a usocket.
Returns NIL if the platform is not supported."
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

(defun %make-binary-fd-stream (fd direction)
  "Create a binary (unsigned-byte 8) stream on the given file descriptor.
DIRECTION is :io, :input, or :output."
  (ecase direction
    (:io
     #+sbcl
     (sb-sys:make-fd-stream fd
                             :input t :output t
                             :element-type '(unsigned-byte 8)
                             :buffering :full
                             :name "telnet-binary-stream")
     #+ccl
     (ccl:make-fd-stream fd :direction :io :element-type '(unsigned-byte 8))
     #+ecl
     (ext:make-stream-from-fd fd :direction :io :element-type '(unsigned-byte 8))
     #-(or sbcl ccl ecl)
     (error "telnet: unsupported Lisp implementation."))
    (:input
     #+sbcl
     (sb-sys:make-fd-stream fd
                             :input t
                             :element-type '(unsigned-byte 8)
                             :buffering :full
                             :name "telnet-binary-input-stream")
     #+ccl
     (ccl:make-fd-stream fd :direction :input :element-type '(unsigned-byte 8))
     #+ecl
     (ext:make-stream-from-fd fd :direction :input :element-type '(unsigned-byte 8))
     #-(or sbcl ccl ecl)
     (error "telnet: unsupported Lisp implementation."))
    (:output
     #+sbcl
     (sb-sys:make-fd-stream fd
                             :output t
                             :element-type '(unsigned-byte 8)
                             :buffering :full
                             :name "telnet-binary-output-stream")
     #+ccl
     (ccl:make-fd-stream fd :direction :output :element-type '(unsigned-byte 8))
     #+ecl
     (ext:make-stream-from-fd fd :direction :output :element-type '(unsigned-byte 8))
     #-(or sbcl ccl ecl)
     (error "telnet: unsupported Lisp implementation."))))

;;; ----------------------------------------------------------------
;;; Telnet connection class
;;; ----------------------------------------------------------------

(defclass telnet-connection ()
  ((usocket
    :initarg :usocket
    :reader telnet-conn-usocket
    :documentation "The usocket for this connection (kept for close/disconnect).")
   (raw-stream
    :initarg :raw-stream
    :reader telnet-conn-raw-stream
    :documentation "Binary (unsigned-byte 8) stream to the socket.")
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
    :documentation "Accumulator for UTF-8 bytes being read from the socket.
After IAC processing, non-command bytes land here before being decoded
into characters.")
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
;;; Construction
;;; ----------------------------------------------------------------

(defun make-telnet-connection (usocket)
  "Create a new telnet-connection from an accepted usocket.

Performs initial telnet option negotiation (sends WILL/WONT/DO/DONT sequence)
and returns a ready-to-use telnet-connection.

USOCKET must be a usocket:stream-usocket from usocket:socket-accept."
  (let* ((fd (%socket-fd usocket))
         (raw-stream (%make-binary-fd-stream fd :io))
         (protocol (make-instance 'telnet-protocol))
         (conn (make-instance 'telnet-connection
                              :usocket usocket
                              :raw-stream raw-stream
                              :protocol protocol)))
    ;; Perform initial option negotiation
    (let ((init-cmds (telnet-init-negotiation protocol)))
      (dolist (cmd init-cmds)
        (handler-case
            (write-sequence cmd raw-stream)
          (stream-error (e)
            (declare (ignore e))
            (setf (telnet-connection-alive-p conn) nil)
            (return-from make-telnet-connection conn))))
      (force-output raw-stream))
    conn))

;;; ----------------------------------------------------------------
;;; Internal: Read a single byte, handling errors
;;; ----------------------------------------------------------------

(defun %read-byte-into (stream buffer pos)
  "Read one byte from STREAM and store it at POS in BUFFER.
Returns the byte value, or :eof if the stream is exhausted,
or signals telnet-connection-lost on error."
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

Side-effects: may write negotiation responses to the raw stream."
  (let ((protocol (telnet-conn-protocol conn))
        (raw-stream (telnet-conn-raw-stream conn)))
    (cond
      ;; Inside subnegotiation
      ((telnet-in-subneg-p protocol)
       (let ((buf (telnet-subneg-buffer protocol)))
         (cond
           ;; IAC SE — end subnegotiation
           ((and (> (fill-pointer buf) 0)
                 (= (aref buf (1- (fill-pointer buf))) iac)
                 (= byte se))
            ;; Remove the trailing IAC from buffer
            (decf (fill-pointer buf))
            (let ((option (aref buf 0))
                  (data (make-array (- (fill-pointer buf) 1)
                                    :element-type '(unsigned-byte 8))))
              (when (> (length data) 0)
                (replace data buf :start2 1))
              (setf (fill-pointer buf) 0)
              (setf (telnet-in-subneg-p protocol) nil)
              ;; Process the completed subneg
              (let ((responses (telnet-process-subnegotiation protocol option data)))
                (dolist (resp responses)
                  (handler-case (write-sequence resp raw-stream)
                    (error () nil)))
                (when responses (force-output raw-stream)))))
           ;; IAC not followed by SE — accumulate IAC and this byte
           ((and (> (fill-pointer buf) 0)
                 (= (aref buf (1- (fill-pointer buf))) iac)
                 (= byte iac))
            ;; IAC IAC inside subneg — keep one IAC as literal data
            (vector-push-extend byte buf))
           ;; Normal subneg byte
           (t
            (vector-push-extend byte buf)))
         :subneg-incomplete))

      ;; Outside subnegotiation, IAC received
      ((= byte iac)
       :iac-pending)

      ;; Regular data byte — accumulate into read buffer
      (t
       (vector-push-extend byte (slot-value conn 'read-buffer))
       :data))))

;;; ----------------------------------------------------------------
;;; Internal: Handle a telnet command (called after IAC + command-byte)
;;; ----------------------------------------------------------------

(defun %handle-telnet-command (conn command option)
  "Process a telnet command (IAC COMMAND [OPTION]).
Writes any negotiation responses to the raw stream."
  (let ((protocol (telnet-conn-protocol conn))
        (raw-stream (telnet-conn-raw-stream conn)))
    (cond
      ;; Subnegotiation begin (SB = 250)
      ((= command sb)
       (setf (telnet-in-subneg-p protocol) t)
       (setf (fill-pointer (telnet-subneg-buffer protocol)) 0))

      ;; No Operation (NOP = 241) — keepalive ack, silently ignore
      ((= command nop) nil)

      ;; Data Mark (DM = 242) — silently ignore (we don't use urgent data)
      ((= command dm) nil)

      ;; WILL/WONT/DO/DONT — option negotiation
      ((or (= command will) (= command wont) (= command do) (= command dont))
       (let ((responses (telnet-process-command protocol command option)))
         (dolist (resp responses)
           (handler-case
               (write-sequence resp raw-stream)
             (error () nil)))
         (when responses
           (force-output raw-stream))))

      ;; Other commands (AYT, IP, AO, BREAK, etc.) — silently ignore
      (t nil))))

;;; ----------------------------------------------------------------
;;; Internal: Decode accumulated UTF-8 bytes to characters
;;; ----------------------------------------------------------------

(defun %flush-read-buffer (conn)
  "Decode accumulated bytes in the read buffer to characters,
appending them to the line buffer.  Clears the read buffer."
  (let ((buf (slot-value conn 'read-buffer))
        (line (slot-value conn 'line-buffer)))
    (when (> (fill-pointer buf) 0)
      (let* ((bytes (make-array (fill-pointer buf)
                                :element-type '(unsigned-byte 8)
                                :initial-contents buf))
             (str (handler-case
                      (flexi-streams:octets-to-string bytes :external-format :utf-8)
                    (error ()
                      ;; On decode error, use replacement chars
                      (flexi-streams:octets-to-string
                       bytes :external-format '(:utf-8 :replacement #\?))))))
        (setf (fill-pointer buf) 0)
        (loop for c across str do (vector-push-extend c line))))))

;;; ----------------------------------------------------------------
;;; Public: Read a single character (with timeout)
;;; ----------------------------------------------------------------

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
        ;; Shift buffer left
        (replace line line :start2 1 :end2 (fill-pointer line))
        (decf (fill-pointer line))
        (return-from telnet-read-char (values c nil))))

    ;; Check for data availability
    (let ((socket (telnet-conn-usocket conn)))
      (when socket
        (let ((ready (handler-case
                         (usocket:wait-for-input socket :timeout timeout :ready-only t)
                       (error () nil))))
          (when (null ready)
            (return-from telnet-read-char (values nil :timeout))))))

    ;; Read and process bytes
    (let* ((raw-stream (telnet-conn-raw-stream conn))
           (buf (slot-value conn 'read-buffer)))
      ;; Clear read buffer
      (setf (fill-pointer buf) 0)

      ;; Read one byte
      (let ((b (%read-byte-into raw-stream buf 0)))
        (when (eq b :eof)
          (setf (telnet-connection-alive-p conn) nil)
          (return-from telnet-read-char (values nil :eof)))

        ;; Process the byte
        (if (= b iac)
            ;; IAC — read the command byte
            (let ((cmd (%read-byte-into raw-stream buf 1)))
              (when (eq cmd :eof)
                (setf (telnet-connection-alive-p conn) nil)
                (return-from telnet-read-char (values nil :eof)))

              (cond
                ;; IAC IAC — literal 255 data byte
                ((= cmd iac)
                 (vector-push-extend iac buf)
                 (%flush-read-buffer conn))

                ;; IAC SB — enter subnegotiation
                ((= cmd sb)
                 (setf (telnet-in-subneg-p (telnet-conn-protocol conn)) t)
                 (setf (fill-pointer (telnet-subneg-buffer (telnet-conn-protocol conn))) 0)
                 ;; Read subneg data until IAC SE
                 (loop
                   (let ((sbb (%read-byte-into raw-stream buf 0)))
                     (when (eq sbb :eof)
                       (setf (telnet-connection-alive-p conn) nil)
                       (return-from telnet-read-char (values nil :eof)))
                     (%process-incoming-byte conn sbb)
                     (when (not (telnet-in-subneg-p (telnet-conn-protocol conn)))
                       (return)))))

                ;; WILL/WONT/DO/DONT — option negotiation (3-byte)
                ((or (= cmd will) (= cmd wont) (= cmd do) (= cmd dont))
                 (let ((opt (%read-byte-into raw-stream buf 2)))
                   (when (eq opt :eof)
                     (setf (telnet-connection-alive-p conn) nil)
                     (return-from telnet-read-char (values nil :eof)))
                   (%handle-telnet-command conn cmd opt)))

                ;; Other 2-byte commands (NOP, DM, AYT, IP, AO, BREAK, EC, EL, GA)
                (t
                 (%handle-telnet-command conn cmd 0)))))

            ;; Not IAC — data byte, already in buf
            (%flush-read-buffer conn)))

      ;; Try to return a character from the line buffer
      (when (> (fill-pointer line) 0)
        (let ((c (aref line 0)))
          (replace line line :start2 1 :end2 (fill-pointer line))
          (decf (fill-pointer line))
          (return-from telnet-read-char (values c nil))))

      ;; No character yet — data was consumed by protocol processing
      ;; Return timeout so caller retries
      (values nil :timeout)))

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
Returns (values nil :connection-lost) on error."
  (let* ((deadline (+ (get-internal-real-time)
                      (* timeout internal-time-units-per-second)))
         (line (slot-value conn 'line-buffer))
         (saw-cr nil))
    ;; Clear any leftover data in line buffer
    (setf (fill-pointer line) 0)
    (setf (fill-pointer (slot-value conn 'read-buffer)) 0)

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
            ((and (null char) (eq status :timeout))
             ;; No data yet, keep polling (caller should send keepalive)
             nil)

            ((and (null char) (or (eq status :eof) (eq status :connection-lost)))
             (return (values nil status)))

            ;; CR — could be CR LF or CR NUL
            ((char= char #\Return)
             (setf saw-cr t))

            ;; LF after CR — line complete
            ((and saw-cr (char= char #\Newline))
             (let ((result (coerce line 'string)))
               (setf (fill-pointer line) 0)
               (return (values result nil))))

            ;; NUL after CR — line complete (RFC 854)
            ((and saw-cr (char= char #\Null))
             (let ((result (coerce line 'string)))
               (setf (fill-pointer line) 0)
               (return (values result nil))))

            ;; LF without CR — line complete (non-standard but common)
            ((char= char #\Newline)
             (let ((result (coerce line 'string)))
               (setf (fill-pointer line) 0)
               (return (values result nil))))

            ;; Any other char after CR — the CR was standalone
            (saw-cr
             (setf saw-cr nil)
             (vector-push-extend #\Return line)
             (vector-push-extend char line))

            ;; Normal character
            (t
             (vector-push-extend char line))))))))

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
    (let* ((raw-stream (telnet-conn-raw-stream conn))
           ;; Encode string to UTF-8 bytes
           (octets (flexi-streams:string-to-octets string :external-format :utf-8))
           ;; Add line ending
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
  "Write raw bytes to the connection.  Useful for sending protocol
commands without IAC escaping."
  (unless (telnet-connection-alive-p conn)
    (error 'telnet-connection-lost :message "Connection is closed"))

  (bordeaux-threads:with-lock-held ((telnet-conn-lock conn))
    (handler-case
        (progn
          (write-sequence byte-vector (telnet-conn-raw-stream conn))
          (force-output (telnet-conn-raw-stream conn)))
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
  "Send a Telnet NOP (No Operation) command.
This is the RFC 854-compliant way to verify the connection is still alive
without sending any application data."
  (handler-case
      (telnet-write-raw conn (make-command-1 nop))
    (telnet-connection-lost ()
      nil)
    (telnet-error ()
      nil)))

;;; ----------------------------------------------------------------
;;; Public: Close the connection
;;; ----------------------------------------------------------------

(defun telnet-connection-close (conn)
  "Close the telnet connection gracefully."
  (when (telnet-connection-alive-p conn)
    (setf (telnet-connection-alive-p conn) nil)
    (handler-case
        (progn
          (when (telnet-conn-raw-stream conn)
            (close (telnet-conn-raw-stream conn)))
          (when (telnet-conn-usocket conn)
            (usocket:socket-close (telnet-conn-usocket conn))))
      (error ()
        nil)))
  nil)

;;; ----------------------------------------------------------------
;;; Public: Stream access (for use as drop-in replacement)
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
