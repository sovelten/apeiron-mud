(in-package #:mud)

(defvar *server-running* nil)
(defvar *server-socket* nil)
(defvar *acceptance-thread* nil
  "The thread handling incoming connections")
(defvar *player-threads* (make-hash-table :test #'equal))
(defvar *server-lock* (bordeaux-threads:make-lock "server-lock"))

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
  (when (and session (session-socket session))
    (handler-case
        (usocket:socket-close (session-socket session))
      (error (e)
        (mud.utils:log-error "Error closing socket for ~A: ~A"
                             (session-socket session) e)))))

(defun session-send-message (session message &key (newline t))
  "Send a message to a session. If NEWLINE is nil, don't add a trailing newline."
  (when session
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

(defun ask-name (session default)
  (session-send-message session "What is your name?")
  (let* ((socket (session-socket session))
         (stream (handler-case (usocket:socket-stream socket) (error () nil))))
    (if (null stream)
        ;; Socket is closed, exit loop
        default
        ;; Socket is open, continue
        (progn
          (session-send-prompt session)
          (let ((line (read-line stream nil nil)))
            (if line
                (let ((trimmed (string-trim '(#\Return #\Newline) line)))
                  (if (and trimmed (> (length trimmed) 0))
                      trimmed
                      default))
                default))))))

(defun handle-client (session)
  "Main loop for handling a client connection."
  (let* ((guest-name (format nil "Guest~D" (random 10000)))
         (char-name (ask-name session guest-name))
         (character (create-character char-name session)))
    (mud.utils:log-message "New connection: ~A" char-name)
    (world-new-character character)
    (session-send-message session (room-describe (object-location character)))
    (session-send-message session "Welcome to the MUD!")
    (handler-case
        (let ((socket (session-socket session)))
          (loop while *server-running*
                do
                   (handler-case
                       (let ((stream (handler-case
                                         (usocket:socket-stream socket)
                                       (error () nil))))
                         (if (null stream)
                             ;; Socket is closed, exit loop
                             (return)
                             ;; Socket is open, continue
                             (progn
                               ;; Send prompt
                               (session-send-prompt session)

                               ;; Receive input
                               (let ((line (read-line stream nil nil)))
                                 (if line
                                     (let ((trimmed (string-trim '(#\Return #\Newline) line)))
                                       (when (and trimmed (> (length trimmed) 0))
                                         (process-command character trimmed)))
                                     (progn
                                       (mud.utils:log-message "Client ~A disconnected (EOF)" char-name)
                                       (return)))))))
                     (end-of-file ()
                       ;; Connection closed by client
                       (mud.utils:log-message "Client ~A disconnected" char-name)
                       (return))
                     (error (e)
                       ;; Check if this is a "broken pipe" or similar connection error
                       (let ((error-str (format nil "~A" e)))
                         (if (or (search "Broken pipe" error-str)
                                 (search "closed" error-str))
                             ;; Connection error, exit gracefully
                             (progn
                               (mud.utils:log-message "Client ~A connection lost" char-name)
                               (return))
                             ;; Other error, log it
                             (progn
                               (mud.utils:log-error "Error in client handler: ~A" e)
                               (return))))))))
      (error (e)
        (mud.utils:log-error "Client handler error for ~A: ~A" char-name e))))

  ;; Cleanup when disconnected
  (let ((session-id (session-id session)))
    (mud.utils:log-message "Attempting to remove thread for session ~A" session-id)
    (remhash session-id *player-threads*))
  (player-disconnect (session-character session)))

(defun accept-connections ()
  "Accept incoming client connections."
  (handler-case
      (loop while *server-running*
            do
               (handler-case
                   (let ((client-socket (usocket:socket-accept *server-socket*)))
                     (when client-socket
                       (let ((session (create-session client-socket)))
                         ;; Start session thread
                         (let ((thread (bordeaux-threads:make-thread
                                        (lambda () (handle-client session))
                                        :name (format nil "session-~A" (session-id session)))))
                           (mud.utils:log-message "Thread for session ~A created" (session-id session))
                           (setf (gethash (session-id session) *player-threads*) thread)))))
                 (usocket:timeout-error ()
                   ;; Just a timeout, continue accepting
                   nil)
                 (error (e)
                   (mud.utils:log-error "Error accepting connection: ~A" e))))
    (error (e)
      (mud.utils:log-error "Accept connections error: ~A" e))))

(defun start-mud-server (&key (host *server-host*) (port *server-port*))
  "Start the MUD server."
  (bordeaux-threads:with-lock-held (*server-lock*)
    (if *server-running*
        (progn
          (mud.utils:log-error "Server is already running!")
          (return-from start-mud-server nil))
        (progn
          ;; Initialize world
          (world-initialize)
          
          ;; Create server socket
          (setf *server-socket* (usocket:socket-listen host port 
                                                       :reuse-address t
                                                       :backlog 5))
          (setf *server-running* t)
          
          (mud.utils:log-message "MUD Server started on ~A:~D" host port)
          
          ;; Start acceptance thread and store reference
          (setf *acceptance-thread*
                (bordeaux-threads:make-thread #'accept-connections :name "accept-connections"))
          
          t))))

(defun stop-mud-server ()
  "Stop the MUD server."
  (bordeaux-threads:with-lock-held (*server-lock*)
    (when *server-running*
      (setf *server-running* nil)
      
      ;; Close server socket first (this will unblock socket-accept)
      (when *server-socket*
        (handler-case
            (usocket:socket-close *server-socket*)
          (error (e)
            (mud.utils:log-error "Error closing server socket: ~A" e)))
        (setf *server-socket* nil))
      
      ;; Wait for acceptance thread to exit
      (when *acceptance-thread*
        (handler-case
            (bordeaux-threads:join-thread *acceptance-thread*)
          (error (e)
            (mud.utils:log-error "Error joining acceptance thread: ~A" e)))
        (setf *acceptance-thread* nil))
      
      ;; Disconnect all players
      (dolist (player (world-all-players))
        (player-disconnect player))
      
      (mud.utils:log-message "MUD Server stopped")
      t)))

(defun get-server-status ()
  "Get the current status of the server."
  (format nil "Server running: ~A~%Players online: ~D~%Rooms in world: ~D~%"
          (if *server-running* "Yes" "No")
          (hash-table-count *players*)
          (hash-table-count *world*)))
