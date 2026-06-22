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

(defun %make-binary-fd-stream (fd)
  "Create a binary (unsigned-byte 8) I/O stream on the given file descriptor.
The stream does NO character encoding — byte I/O is direct."
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
    :documentation "Binary (unsigned-byte 8) stream to the socket.
All I/O goes through this stream.  Telnet protocol commands are
read/written directly.  Application data is encoded/decoded via
flexi-streams:string-to-octets and octets-to-string.")
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
    :documentation "Accumulator for UTF-8 bytes after IAC processing.
Decoded to characters via flexi-streams:octets-to-string.")
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
  "Create a new telnet-connection from a usocket.

Duplicates the socket FD to create a dedicated binary stream, keeping
the usocket's character stream open only for compatibility (it is
never read from).  Performs initial RFC 854 option negotiation.

USOCKET must be a usocket:stream-usocket from usocket:socket-accept
or usocket:socket-connect."
  (let* ((fd (%socket-fd usocket))
         ;; Duplicate the FD so the binary stream has its own
         ;; independent file descriptor.  This prevents the usocket
         ;; character stream's buffer from stealing data meant for us.
         (binary-fd (sb-posix:dup fd))
         (raw-stream (%make-binary-fd-stream binary-fd))
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
Writes any negotiation responses to the raw stream."
  (let ((protocol (telnet-conn-protocol conn))
        (raw-stream (telnet-conn-raw-stream conn)))
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
;;; Internal: Decode accumulated UTF-8 bytes to characters
;;; ----------------------------------------------------------------

(defun %flush-read-buffer (conn)
  "Decode accumulated bytes in the read buffer to characters,
appending them to the line buffer.  Uses flexi-streams for UTF-8 decode."
  (let ((buf (slot-value conn 'read-buffer))
        (line (slot-value conn 'line-buffer)))
    (when (> (fill-pointer buf) 0)
      (let* ((bytes (make-array (fill-pointer buf)
                                :element-type '(unsigned-byte 8)
                                :initial-contents buf))
             (str (handler-case
                      (flexi-streams:octets-to-string bytes :external-format :utf-8)
                    (error ()
                      (flexi-streams:octets-to-string
                       bytes
                       :external-format (flexi-streams:make-external-format
                                         :utf-8 :replacement #\?))))))
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
        (replace line line :start2 1 :end2 (fill-pointer line))
        (decf (fill-pointer line))
        (return-from telnet-read-char (values c nil))))

    ;; Check for data availability using listen on the binary stream.
    ;; We use listen (not usocket:wait-for-input) because the usocket
    ;; character stream would steal bytes from the kernel buffer.
    (let* ((raw-stream (telnet-conn-raw-stream conn))
           (deadline (+ (get-internal-real-time)
                        (* timeout internal-time-units-per-second))))
      (loop
        (when (listen raw-stream)
          (return))
        (let ((remaining (- deadline (get-internal-real-time))))
          (when (<= remaining 0)
            (return-from telnet-read-char (values nil :timeout)))
          (sleep (min 0.05 (/ remaining internal-time-units-per-second))))))

    ;; Read and process bytes from the raw binary stream
    (let* ((raw-stream (telnet-conn-raw-stream conn))
           (buf (slot-value conn 'read-buffer)))
      (setf (fill-pointer buf) 0)

      (let ((b (%read-byte-into raw-stream buf 0)))
        (when (eq b :eof)
          (setf (telnet-connection-alive-p conn) nil)
          (return-from telnet-read-char (values nil :eof)))

        (if (= b iac)
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
                 (%handle-telnet-command conn cmd 0)))))

            ;; Not IAC — data byte, already in buf, decode it
            (setf (fill-pointer buf) 1)
            (%flush-read-buffer conn)))

      ;; Try to return a character from the line buffer
      (when (> (fill-pointer line) 0)
        (let ((c (aref line 0)))
          (replace line line :start2 1 :end2 (fill-pointer line))
          (decf (fill-pointer line))
          (return-from telnet-read-char (values c nil))))

      ;; No character yet — data was consumed by protocol processing
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
            ((and (null char) (eq status :timeout)) nil)

            ((and (null char) (or (eq status :eof) (eq status :connection-lost)))
             (return (values nil status)))

            ((char= char #\Return)
             (setf saw-cr t))

            ((and saw-cr (char= char #\Newline))
             (let ((result (coerce line 'string)))
               (setf (fill-pointer line) 0)
               (return (values result nil))))

            ((and saw-cr (char= char #\Nul))
             (let ((result (coerce line 'string)))
               (setf (fill-pointer line) 0)
               (return (values result nil))))

            ((char= char #\Newline)
             (let ((result (coerce line 'string)))
               (setf (fill-pointer line) 0)
               (return (values result nil))))

            (saw-cr
             (setf saw-cr nil)
             (vector-push-extend #\Return line)
             (vector-push-extend char line))

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
          ;; Close the binary stream first
          (when (telnet-conn-raw-stream conn)
            (close (telnet-conn-raw-stream conn)))
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
