(in-package #:mud)

(defvar *server-running* nil)
(defvar *server-socket* nil)
(defvar *acceptance-thread* nil
  "The thread handling incoming connections")
(defvar *player-threads* (make-hash-table :test #'equal))
(defvar *server-lock* (bordeaux-threads:make-lock "server-lock"))

(defun handle-client (world session)
  "Main loop for handling a client connection."
  (let* ((guest-name (format nil "Guest~D" (random 10000)))
         (char-name (ask-input session "What is your name?" guest-name))
         (character (new-character char-name session)))
    (mud.utils:log-message "New connection: ~A" char-name)
    (world-add-character! world character)
    (mud-write session (room-describe (object-location character)))
    (mud-write session "Welcome to the MUD!")
    (handler-case
        (loop while *server-running*
              do
                 (handler-case
                     (progn
                       ;; Send prompt
                       (session-send-prompt session)

                       (multiple-value-bind (line status) (read-line-with-timeout-loop session)
                         (cond
                           ((eq status :timeout)
                            (mud-write session "Timed out due to inactivity.")
                            (mud.utils:log-message "Client ~A timed out due to inactivity" char-name)
                            (return))
                           ((or (eq status :eof) (typep status 'error))
                            (mud.utils:log-message "Client ~A disconnected ~A" char-name status)
                            (return))
                           (line
                            (let ((trimmed (string-trim '(#\Return #\Newline) line)))
                              (when (and trimmed (> (length trimmed) 0))
                                (process-command world character trimmed))))
                           (t
                            (return)))))
                   (end-of-file ()
                     ;; Connection closed by client
                     (mud.utils:log-message "Client ~A disconnected end-of-file" char-name)
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
                             (return)))))))
      (error (e)
        (mud.utils:log-error "Client handler error for ~A: ~A" char-name e))))

  ;; Cleanup when disconnected
  (let ((session-id (session-id session)))
    (mud.utils:log-message "Attempting to remove thread for session ~A" session-id)
    (remhash session-id *player-threads*)
    (when (session-character session)
      (world-remove-character! world (session-character session)))
    (session-disconnect session)))

(defun accept-connections (world)
  "Accept incoming client connections."
  (handler-case
      (loop while *server-running*
            do
               (handler-case
                   (let ((client-socket (usocket:socket-accept *server-socket*)))
                     (when client-socket
                       (if (not *server-running*)
                           (usocket:socket-close client-socket)
                           (let ((session (new-telnet-session client-socket)))
                             ;; Start session thread
                             (let ((thread (bordeaux-threads:make-thread
                                            (lambda () (handle-client world session))
                                            :name (format nil "session-~A" (session-id session)))))
                               (mud.utils:log-message "Thread for session ~A created" (session-id session))
                               (setf (gethash (session-id session) *player-threads*) thread))))))
                 (usocket:timeout-error ()
                   ;; Just a timeout, continue accepting
                   nil)
                 (error (e)
                   ;; If the server is stopping, ignore socket errors from closed listening socket
                   (when *server-running*
                     (mud.utils:log-error "Error accepting connection: ~A" e)))))
    (error (e)
      (when *server-running*
        (mud.utils:log-error "Accept connections error: ~A" e)))))

(defun start-mud-server (&key (host *server-host*) (port *server-port*) force-new)
  "Start the MUD server."
  (bordeaux-threads:with-lock-held (*server-lock*)
    (if *server-running*
        (progn
          (mud.utils:log-error "Server is already running!")
          (return-from start-mud-server nil))
        ;; Initialize world
        (let ((world (world-restore-or-initialize :force-new force-new)))
          (setf *server-socket*
                (usocket:socket-listen host port :reuse-address t :backlog 5))
          (setf *server-running* t)
          (mud.utils:log-message "MUD Server started on ~A:~D" host port)
          (setf *acceptance-thread*
                (bordeaux-threads:make-thread (lambda () (accept-connections world)) :name "accept-connections"))
          t))))

(defun stop-mud-server ()
  "Stop the MUD server."
  (bordeaux-threads:with-lock-held (*server-lock*)
    (when *server-running*
      (setf *server-running* nil)
      
      ;; Fire a dummy connection to unblock socket-accept if it is blocked
      (when *server-socket*
        (handler-case
            (let ((port (usocket:get-local-port *server-socket*)))
              (when port
                (let ((dummy (usocket:socket-connect "127.0.0.1" port)))
                  (usocket:socket-close dummy))))
          (error () nil)))
      
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
      (let ((world (get-persistent-world)))
        (dolist (player (characters world))
          (world-remove-character! world player)
          (session-disconnect (character-session player))))
      
      (mud.utils:log-message "MUD Server stopped")
      t)))

(defun get-server-status ()
  "Get the current status of the server."
  (format nil "Server running: ~A~%Players online: ~D~%Rooms in world: ~D~%"
          (if *server-running* "Yes" "No")
          (world-total-players (get-persistent-world))
          (total-rooms)))
