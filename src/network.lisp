(in-package #:mud)

(defvar *server-running* nil)
(defvar *server-socket* nil)
(defvar *acceptance-thread* nil
  "The thread handling incoming connections")
(defvar *player-threads* (make-hash-table :test #'equal))
(defvar *server-lock* (bordeaux-threads:make-lock "server-lock"))

(defclass mud-session ()
  ((socket :initarg :socket
           :accessor session-socket
           :documentation "Network socket for this session")
   (character :initarg :player
              :accessor session-character
              :initform nil
              :documentation "Player controlled by this session"))
  (:documentation "A network session in the MUD"))

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

(defun handle-client (player)
  "Main loop for handling a client connection."
  (let ((session (player-session player)))
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
                                      (process-command player trimmed)))
                                  (progn
                                    (mud.utils:log-message "Client ~A disconnected (EOF)" (object-name player))
                                    (return)))))))
                  (end-of-file ()
                    ;; Connection closed by client
                    (mud.utils:log-message "Client ~A disconnected" (object-name player))
                    (return))
                  (error (e)
                    ;; Check if this is a "broken pipe" or similar connection error
                    (let ((error-str (format nil "~A" e)))
                      (if (or (search "Broken pipe" error-str)
                              (search "closed" error-str))
                          ;; Connection error, exit gracefully
                          (progn
                            (mud.utils:log-message "Client ~A connection lost" (object-name player))
                            (return))
                          ;; Other error, log it
                          (progn
                            (mud.utils:log-error "Error in client handler: ~A" e)
                            (return))))))))
      (error (e)
        (mud.utils:log-error "Client handler error for ~A: ~A" (object-name player) e)))
    
    ;; Cleanup when disconnected
    (let ((player-id (object-id player)))
      (mud.utils:log-message "Attempting to remove thread for player ~A" player-id)
      (remhash player-id *player-threads*))
    (player-disconnect player)))

(defun accept-connections ()
  "Accept incoming client connections."
  (handler-case
      (loop while *server-running*
            do
               (handler-case
                   (let ((client-socket (usocket:socket-accept *server-socket*)))
                     (when client-socket
                       (let* ((guest-name (format nil "Guest~D" (random 10000)))
                              (session (make-instance 'mud-session :socket client-socket))
                              (character (create-character guest-name session)))
                         (session-send-message session "Welcome to the MUD!")
                         (session-send-message session "What is your name?")
                         (let ((stream (handler-case (usocket:socket-stream client-socket) (error () nil))))
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
                                           (setf (object-name character) trimmed)))
                                       (progn
                                         (mud.utils:log-message "Client ~A disconnected (EOF)" (object-name character))
                                         (return)))))))
                         (mud.utils:log-message "New connection: ~A" (object-name character))
                         (world-new-character character)
                         (session-send-message session (room-describe (object-location character)))
                         ;; Start session thread
                         (let ((thread (bordeaux-threads:make-thread
                                        (lambda () (handle-client character))
                                        :name (format nil "player-~A" (object-id character)))))
                           (setf (gethash (object-id character) *player-threads*) thread)))))
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
