(in-package :mud)

(defclass mud-session ()
  ((id :initarg :id
       :accessor session-id
       :documentation "Unique identifier for this object")
   (socket :initarg :socket
           :accessor session-socket
           :documentation "Network socket for this session")
   (character :initarg :player
              :accessor session-character
              :initform nil
              :documentation "Player controlled by this session"))
  (:documentation "A network session in the MUD"))

;; On timeout, should send :timeout on second return value
(defgeneric mud-read-line (obj &key timeout))
(defgeneric mud-write (obj message &key newline))

(defun new-session (socket)
  (make-instance 'mud-session
                 :id (mud.utils:make-id)
                 :socket socket))

(defun session-disconnect (session)
  ;; Unlink character from session before disconnecting
  ;; Is this the best approach?
  (when (session-character session)
    (setf (session-character session) nil))
  (when (and session (session-socket session))
    (handler-case
        (usocket:socket-close (session-socket session))
      (error (e)
        (mud.utils:log-error "Error closing socket for ~A: ~A"
                             (session-socket session) e)))))

(defun session-send-message (session message &key (newline t))
  "Send a message to a session. If NEWLINE is nil, don't add a trailing newline."
  (when (and session (session-socket session))
    (handler-case
        (let ((stream (usocket:socket-stream (session-socket session))))
          (when stream
            (if newline
                (format stream "~A~%" message)
                (format stream "~A" message))
            (force-output stream)))
      (error (e)
        ;; Only log if it's not a connection error
        (let ((error-str (format nil "~A" e)))
          (unless (or (search "Broken pipe" error-str)
                      (search "closed" error-str))
            (mud.utils:log-error "Failed to send message to session ~A: ~A"
                                 (session-socket session) e)))))))

(defun session-send-prompt (session)
  "Send a prompt to a player on the same line (no newline)."
  (session-send-message session "> " :newline nil))

(defun read-line-with-timeout (socket &optional (timeout 300))
  "Read a line from socket stream with a timeout in seconds.
   Returns (values line status), where status is nil for success,
   :timeout for timeout, and :eof for connection closed."
  (if (null socket)
      (values nil :eof)
      (let ((ready (handler-case (usocket:wait-for-input socket :timeout timeout :ready-only t)
                     (error () nil))))
        (if (null ready)
            (values nil :timeout)
            (let ((stream (handler-case (usocket:socket-stream socket) (error () nil))))
              (if (null stream)
                  (values nil :eof)
                  (handler-case
                      (let ((line (read-line stream nil nil)))
                        (if line
                            (values line nil)
                            (values nil :eof)))
                    (error (e)
                      (values nil e)))))))))

(defmethod mud-read-line ((obj mud-session) &key (timeout 300))
  (let ((socket (session-socket obj)))
    (read-line-with-timeout socket timeout)))

(defmethod mud-write ((obj mud-session) message &key (newline t))
  (session-send-message obj message :newline newline))

(defun send-keepalive (socket)
  "Send a harmless Telnet NOP (No Operation) command to keep the connection alive.
   This complies with RFC 854 and is ignored by compliant Telnet clients without shifting the cursor.
   If the socket's connection has been lost, this write or its flush will signal an error."
  (when socket
    (let ((stream (usocket:socket-stream socket)))
      (mud.utils:log-message "Staying alive with Telnet NOP...")
      (when stream
        (force-output stream)
        #+sbcl
        (let* ((fd (sb-sys:fd-stream-fd stream))
               (octets (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(255 241)))
               (sap (sb-sys:vector-sap octets)))
          (sb-unix:unix-write fd sap 0 2))
        #-sbcl
        (progn
          (write-char (code-char 255) stream)
          (write-char (code-char 241) stream)
          (force-output stream))))))

(defun read-line-with-timeout-loop (socket &key (poll-interval 30) (keepalive-func #'send-keepalive))
  "Read a line from socket stream by polling with a short timeout (POLL-INTERVAL).
   If polling times out, it invokes KEEPALIVE-FUNC (e.g., to send a keepalive probe)
   to verify if the connection is still alive, and then continues waiting.
   This allows players to stay connected indefinitely while actively detecting broken connections."
  (loop
     (multiple-value-bind (line status) (read-line-with-timeout socket poll-interval)
       (cond
         ((null status)
          (return (values line nil)))
         ((eq status :timeout)
          (if keepalive-func
              (handler-case
                  (progn
                    (funcall keepalive-func socket)
                    nil)
                (error (e)
                  (return (values nil e))))
              nil))
         (t
          (return (values nil status)))))))

(defun ask-input (obj question &optional (default ""))
  "Asks input from the user"
  (mud-write obj question :newline t)
  (multiple-value-bind (line status) (mud-read-line obj)
    (if (and line (null status))
        (let ((trimmed (string-trim '(#\Return #\Newline) line)))
          (if (and trimmed (> (length trimmed) 0))
              trimmed
              default))
        default)))
