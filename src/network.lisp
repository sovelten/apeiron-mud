(in-package #:mud)

(defvar *server-running* nil)
(defvar *server-socket* nil)
(defvar *acceptance-thread* nil
  "The thread handling incoming connections")
(defvar *player-threads* (make-hash-table :test #'equal))
(defvar *server-lock* (bordeaux-threads:make-lock "server-lock"))

(defun register-or-login-player (player stream)
  "Handle registration or login for a new connection.
   Returns the persistent player object if successful, NIL otherwise."
  (handler-case
      (progn
        ;; Ask if new player or returning
        (player-send-message player "Welcome to the MUD!")
        (player-send-message player "Are you a new player? (yes/no)")
        (player-send-prompt player)
        
        (let ((response (read-line stream nil nil)))
          (if (null response)
              (return-from register-or-login-player nil)
              (let ((trimmed (string-downcase (string-trim '(#\Return #\Newline #\Space) response))))
                (cond
                  ((or (string= trimmed "yes") (string= trimmed "y"))
                   ;; New player registration
                   (register-new-account player stream))
                  ((or (string= trimmed "no") (string= trimmed "n"))
                   ;; Returning player login
                   (login-returning-player player stream))
                  (t
                   (player-send-message player "Please answer 'yes' or 'no'.")
                   (register-or-login-player player stream)))))))
    (error (e)
      (mud.utils:log-error "Error in registration: ~A" e)
      nil)))

(defun register-new-account (player stream)
  "Handle new player account registration."
  (handler-case
      (loop
        do
        (player-send-message player "Choose a username (alphanumeric, 3-20 characters):")
        (player-send-prompt player)
        (let ((username-input (read-line stream nil nil)))
          (if (null username-input)
              (return-from register-new-account nil))
          
          (let ((username (string-downcase (string-trim '(#\Return #\Newline #\Space) username-input))))
            (cond
              ((< (length username) 3)
               (player-send-message player "Username must be at least 3 characters."))
              ((> (length username) 20)
               (player-send-message player "Username must be at most 20 characters."))
              ((not (every (lambda (c) (or (alphanumericp c) (char= c #\-) (char= c #\_))) username))
               (player-send-message player "Username can only contain letters, numbers, hyphens, and underscores."))
              ((player-exists-p username)
               (player-send-message player "That username is already taken."))
              (t
               ;; Username valid, get password
               (player-send-message player "Choose a password (minimum 6 characters):")
               (player-send-prompt player)
               (let ((password-input (read-line stream nil nil)))
                 (if (null password-input)
                     (return-from register-new-account nil))
                 
                 (let ((password (string-trim '(#\Return #\Newline) password-input)))
                   (if (< (length password) 6)
                       (player-send-message player "Password must be at least 6 characters.")
                       (progn
                         ;; Get display name
                         (player-send-message player "Choose a display name:")
                         (player-send-prompt player)
                         (let ((display-input (read-line stream nil nil)))
                           (if (null display-input)
                               (return-from register-new-account nil))
                           
                           (let ((display-name (string-trim '(#\Return #\Newline) display-input)))
                             (if (zerop (length display-name))
                                 (player-send-message player "Display name cannot be empty.")
                                 (progn
                                   ;; Register the player
                                   (if (register-new-player username password display-name player)
                                       (progn
                                         (setf (player-username player) username)
                                         (setf (object-name player) display-name)
                                         (player-send-message player "Registration successful!")
                                         (return-from register-new-account player))
                                       (player-send-message player "Registration failed.")))))))))))))))
    (error (e)
      (mud.utils:log-error "Registration error: ~A" e)
      nil)))

(defun login-returning-player (player stream)
  "Handle login for returning players."
  (handler-case
      (loop
        do
        (player-send-message player "Enter your username:")
        (player-send-prompt player)
        (let ((username-input (read-line stream nil nil)))
          (if (null username-input)
              (return-from login-returning-player nil))
          
          (let ((username (string-downcase (string-trim '(#\Return #\Newline #\Space) username-input))))
            (if (not (player-exists-p username))
                (player-send-message player "User not found.")
                (progn
                  (player-send-message player "Enter your password:")
                  (player-send-prompt player)
                  (let ((password-input (read-line stream nil nil)))
                    (if (null password-input)
                        (return-from login-returning-player nil))
                    
                    (let ((password (string-trim '(#\Return #\Newline) password-input)))
                      (let ((player-info (validate-login username password)))
                        (if player-info
                            (progn
                              ;; Get or update the persistent player object
                              (let ((persistent-player (update-player-socket username (player-socket player))))
                                (setf (player-username persistent-player) username)
                                (player-send-message persistent-player "Login successful!")
                                (return-from login-returning-player persistent-player)))
                            (player-send-message player "Incorrect password."))))))))))
    (error (e)
      (mud.utils:log-error "Login error: ~A" e)
      nil)))

(defun handle-client (player)
  "Main loop for handling a client connection."
  (handler-case
      (let ((socket (player-socket player)))
        ;; First handle registration/login
        (let ((stream (handler-case
                        (usocket:socket-stream socket)
                        (error () nil))))
          (if (null stream)
              (progn
                (mud.utils:log-message "Socket closed before registration")
                (return-from handle-client nil))
              (let ((registered-player (register-or-login-player player stream)))
                (if (null registered-player)
                    (progn
                      (mud.utils:log-message "Registration cancelled or failed")
                      (return-from handle-client nil))
                    ;; Use the registered player (might be persistent if reconnecting)
                    (let ((actual-player registered-player))
                      ;; Add to world if not already there
                      (unless (world-get-player (object-id actual-player))
                        (when *start-room*
                          (room-add-object *start-room* actual-player))
                        (world-add-player actual-player))
                      
                      ;; Send room description
                      (player-send-message actual-player (room-describe (object-location actual-player)))
                      
                      ;; Main game loop
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
                                        (player-send-prompt actual-player)
                                        
                                        ;; Receive input
                                        (let ((line (read-line stream nil nil)))
                                          (if line
                                              (let ((trimmed (string-trim '(#\Return #\Newline) line)))
                                                (when (and trimmed (> (length trimmed) 0))
                                                  (process-command actual-player trimmed)))
                                              (progn
                                                (mud.utils:log-message "Client ~A disconnected (EOF)" (object-name actual-player))
                                                (return)))))))
                              (end-of-file ()
                                ;; Connection closed by client
                                (mud.utils:log-message "Client ~A disconnected" (object-name actual-player))
                                (return))
                              (error (e)
                                ;; Check if this is a "broken pipe" or similar connection error
                                (let ((error-str (format nil "~A" e)))
                                  (if (or (search "Broken pipe" error-str)
                                          (search "closed" error-str))
                                      ;; Connection error, exit gracefully
                                      (progn
                                        (mud.utils:log-message "Client ~A connection lost" (object-name actual-player))
                                        (return))
                                      ;; Other error, log it
                                      (progn
                                        (mud.utils:log-error "Error in client handler: ~A" e)
                                        (return)))))))))))))
    (error (e)
      (mud.utils:log-error "Client handler error for ~A: ~A" (object-name player) e)))
  
  ;; Cleanup when disconnected
  (let ((player-id (object-id player)))
    (mud.utils:log-message "Attempting to remove thread for player ~A" player-id)
    (remhash player-id *player-threads*))
  (player-disconnect player))

(defun accept-connections ()
  "Accept incoming client connections."
  (handler-case
      (loop while *server-running*
            do
            (handler-case
                (let ((client-socket (usocket:socket-accept *server-socket*)))
                  (when client-socket
                    (let ((player-name (format nil "Player~D" (random 10000))))
                      (mud.utils:log-message "New connection: ~A" player-name)
                      
                      ;; Create player
                      (let ((player (create-player player-name client-socket)))
                        ;; Send welcome message
                        (player-send-message player "Welcome to the MUD!")
                        (player-send-message player (room-describe (object-location player)))
                        
                        ;; Start player thread
                        (let ((thread (bordeaux-threads:make-thread
                                      (lambda () (handle-client player))
                                      :name (format nil "player-~A" (object-id player)))))
                          (setf (gethash (object-id player) *player-threads*) thread))))))
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
            (bordeaux-threads:join-thread *acceptance-thread* :timeout 5)
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
