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

(defun create-session (socket)
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
