;;;; src/core/session.lisp — Session abstraction for the MUD core
;;;;
;;;; Defines the protocol and base classes for network sessions, without
;;;; any dependency on the telnet subsystem.  The telnet-specific session
;;;; subclass lives in the server module (src/server/session-telnet.lisp).

(in-package #:apeiron.core)

;; Necessary protocols for user session interaction

;; On timeout, should send :timeout on second return value
(defgeneric mud-read-line (obj &key timeout))
(defgeneric mud-write (obj message &key newline))
(defgeneric session-keepalive (session)
  (:documentation "Send a keepalive heartbeat for this session.
The default method is a no-op."))
(defgeneric session-disconnect (session)
  (:documentation "Clean up and disconnect this session."))

;;
;; MUD Session basic implementation of protocols
;;

(defclass mud-session ()
  ((id :initarg :id
       :initform (make-id)
       :accessor session-id
       :documentation "Unique identifier for this object")
   (character :initarg :player
              :accessor session-character
              :initform nil
              :documentation "Player controlled by this session"))
  (:documentation "A network session in the MUD"))

(defun new-session ()
  "Create a new base mud-session with no backing I/O.
Subclasses with I/O should be used instead (e.g. STREAM-SESSION)."
  (make-instance 'mud-session
                 :id (make-id)))

(defmethod session-keepalive ((session mud-session))
  "Default keepalive is a no-op.  Subclasses (e.g. telnet-session)
should override this to send protocol-specific heartbeats."
  (declare (ignore session))
  nil)

(defmethod session-disconnect ((session mud-session))
  "Disconnect the session — only clears the character link.
Subclasses should close their own resources first and then
call CALL-NEXT-METHOD to clear the character link."
  (when (session-character session)
    (setf (session-character session) nil)))

(defun session-send-prompt (session)
  "Send a prompt to a player on the same line (no newline)."
  (mud-write session "> " :newline nil))

(defmethod mud-read-line ((obj mud-session) &key (timeout 300))
  "Base implementation returns :eof.  Subclasses should override
this method to provide their own line-reading implementation."
  (declare (ignore timeout))
  (values nil :eof))

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

;;
;; Basic Stream Session
;;

(defclass stream-session (mud-session)
  ((stream :initarg :stream
           :reader session-stream
           :initform nil
           :documentation "The stream backing this session"))
  (:documentation "A session backed by a plain Common Lisp stream.
Useful for testing with string streams, or for Telnet-like backends
that provide their own stream abstraction."))

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

(defmethod mud-write ((obj stream-session) message &key (newline t))
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
              (log-error "Failed to send message to session ~D: ~A"
                         (session-id obj) e))))))))

(defmethod session-disconnect ((session stream-session))
  (when (session-stream session)
    (handler-case
        (close (session-stream session))
      (error (e)
        (log-error "Error closing stream for ~A: ~A"
                   (session-stream session) e))))
  (call-next-method))

(defmethod session-keepalive ((session stream-session))
  ;; No keepalive needed for stream-based sessions
  (declare (ignore session))
  nil)
