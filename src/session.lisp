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

(defun new-telnet-session (usocket)
  "Create a new telnet-session from an accepted usocket.
Performs initial RFC 854 telnet option negotiation and returns
a session ready for I/O."
  (make-instance 'telnet-session
                 :id (mud.utils:make-id)
                 :telnet-conn (telnet:make-telnet-connection usocket)))

(defgeneric session-stream (session)
  (:documentation "Return the stream backing this session, or nil."))

(defgeneric session-keepalive (session)
  (:documentation "Send a keepalive heartbeat for this session.
The default method is a no-op."))

(defmethod session-keepalive ((session mud-session))
  "Default keepalive is a no-op.  Subclasses (e.g. telnet-session)
should override this to send protocol-specific heartbeats."
  (declare (ignore session))
  nil)

(defmethod session-stream ((session mud-session))
  (let ((socket (session-socket session)))
    (when socket
      (handler-case (usocket:socket-stream socket)
        (error () nil)))))

(defgeneric session-disconnect (session)
  (:documentation "Clean up and disconnect this session."))

(defmethod session-disconnect ((session mud-session))
  (when (session-character session)
    (setf (session-character session) nil))
  (when (and session (session-socket session))
    (handler-case
        (usocket:socket-close (session-socket session))
      (error (e)
        (mud.utils:log-error "Error closing socket for ~A: ~A"
                             (session-socket session) e)))))

(defmethod mud-write ((obj mud-session) message &key (newline t))
  (let ((stream (session-stream obj)))
    (when stream
      (handler-case
          (progn
            (if newline
                (format stream "~A~%" message)
                (format stream "~A" message))
            (force-output stream))
        (error (e)
          (let ((error-str (format nil "~A" e)))
            (unless (or (search "Broken pipe" error-str)
                        (search "closed" error-str))
              (mud.utils:log-error "Failed to send message to session ~A: ~A"
                                   (session-socket obj) e))))))))

(defun session-send-prompt (session)
  "Send a prompt to a player on the same line (no newline)."
  (mud-write session "> " :newline nil))

(defmethod mud-read-line ((obj mud-session) &key (timeout 300))
  (let ((socket (session-socket obj)))
    (if (null socket)
        (values nil :eof)
        (let ((ready (handler-case (usocket:wait-for-input socket :timeout timeout :ready-only t)
                       (error () nil))))
          (if (null ready)
              (values nil :timeout)
              (let ((stream (session-stream obj)))
                (if (null stream)
                    (values nil :eof)
                    (handler-case
                        (let ((line (read-line stream nil nil)))
                          (if line
                              (values line nil)
                              (values nil :eof)))
                      (error (e)
                        (values nil e))))))))))

(defun read-line-with-timeout-loop (session &key (poll-interval 30))
  "Read a line from SESSION by polling with a short timeout (POLL-INTERVAL).
   If polling times out, it sends a keepalive heartbeat to verify the
   connection is still alive, then continues waiting.
   Returns (values line status)."
  (loop
     (multiple-value-bind (line status) (mud-read-line session :timeout poll-interval)
       (cond
         ((null status)
          (return (values line nil)))
         ((eq status :timeout)
          (handler-case
              (progn
                (session-keepalive session)
                nil)
            (error (e)
              (return (values nil e)))))
         (t
          (return (values nil status)))))))

(defclass stream-session (mud-session)
  ((stream :initarg :stream
           :reader session-stream
           :initform nil
           :documentation "The stream backing this session"))
  (:documentation "A session backed by a plain Common Lisp stream.
Useful for testing with string streams, or for Telnet-like backends
that provide their own stream abstraction."))

(defclass telnet-session (mud-session)
  ((telnet-conn :initarg :telnet-conn
                :reader session-telnet-connection
                :documentation "The telnet:telnet-connection backing this session."))
  (:documentation "A session backed by a telnet:telnet-connection.

This session implements RFC 854-compliant telnet I/O with proper
IAC command processing, option negotiation, and keepalive via NOP.
The telnet subsystem is fully decoupled from MUD game logic."))

(defmethod mud-read-line ((session stream-session) &key (timeout 300))
  (declare (ignore timeout))
  (let ((stream (session-stream session)))
    (if (null stream)
        (values nil :eof)
        (handler-case
            (let ((line (read-line stream nil nil)))
              (if line
                  (values line nil)
                  (values nil :eof)))
          (error (e)
            (values nil e))))))

(defmethod session-disconnect ((session stream-session))
  (when (session-character session)
    (setf (session-character session) nil))
  (when (session-stream session)
    (handler-case
        (close (session-stream session))
      (error (e)
        (mud.utils:log-error "Error closing stream for ~A: ~A"
                             (session-stream session) e)))))

(defmethod session-keepalive ((session stream-session))
  ;; No keepalive needed for stream-based sessions
  (declare (ignore session))
  nil)

(progn
  ;; --- telnet-session methods ---
  (defmethod session-stream ((session telnet-session))
    "Telnet sessions do not expose a raw CL stream.
Use telnet:telnet-read-line / telnet:telnet-write-string instead."
    nil)

  (defmethod session-keepalive ((session telnet-session))
    "Send a Telnet NOP (RFC 854) to keep the connection alive."
    (telnet:telnet-send-nop (session-telnet-connection session)))

  (defmethod mud-read-line ((session telnet-session) &key (timeout 300))
    "Read a line from the telnet session using RFC 854-compliant I/O."
    (let ((conn (session-telnet-connection session)))
      (if conn
          (handler-case
              (telnet:telnet-read-line conn :timeout timeout :poll-interval 0.1)
            (telnet:telnet-connection-lost (e)
              (declare (ignore e))
              (values nil :connection-lost))
            (telnet:telnet-error (e)
              (mud.utils:log-error "Telnet read error: ~A" (telnet:telnet-error-message e))
              (values nil :eof)))
          (values nil :eof))))

  (defmethod mud-write ((session telnet-session) message &key (newline t))
    "Write a message to the telnet session using RFC 854-compliant I/O."
    (let ((conn (session-telnet-connection session)))
      (when conn
        (handler-case
            (telnet:telnet-write-string conn message
                                        :end (if newline :crlf nil))
          (telnet:telnet-connection-lost (e)
            (declare (ignore e))
            nil)
          (telnet:telnet-error (e)
            (mud.utils:log-error "Telnet write error: ~A" (telnet:telnet-error-message e))
            nil)))))

  (defmethod session-disconnect ((session telnet-session))
    "Disconnect the telnet session, releasing all resources."
    (when (session-character session)
      (setf (session-character session) nil))
    (let ((conn (session-telnet-connection session)))
      (when conn
        (handler-case
            (telnet:telnet-connection-close conn)
          (error (e)
            (mud.utils:log-error "Error closing telnet connection: ~A" e)))))))

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
