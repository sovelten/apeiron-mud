(in-package #:apeiron.server)

(defvar *server-running* nil)
(defvar *server-socket* nil)
(defvar *acceptance-thread* nil
  "The thread handling incoming connections")
(defvar *player-threads* (make-hash-table :test #'equal))
(defvar *server-lock* (bordeaux-threads:make-lock "server-lock"))

;; TLS listener
(defvar *server-tls-socket* nil
  "The TLS listening socket (if TLS is enabled).")

(defvar *tls-acceptance-thread* nil
  "The thread handling incoming TLS connections.")

(defun handle-client (world session)
  "Main loop for handling a client connection."
  (let* ((guest-name (format nil "Guest~D" (random 10000)))
         (char-name (ask-input session "What is your name?" guest-name))
         (character (new-character char-name session)))
    (log-message "New connection: ~A" char-name)
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
                            (log-message "Client ~A timed out due to inactivity" char-name)
                            (return))
                           ((or (eq status :eof) (typep status 'error))
                            (log-message "Client ~A disconnected ~A" char-name status)
                            (return))
                           (line
                            (let ((trimmed (string-trim '(#\Return #\Newline) line)))
                              (when (and trimmed (> (length trimmed) 0))
                                (process-command world character trimmed))))
                           (t
                            (return)))))
                   (end-of-file ()
                     ;; Connection closed by client
                     (log-message "Client ~A disconnected end-of-file" char-name)
                     (return))
                   (error (e)
                     ;; Check if this is a "broken pipe" or similar connection error
                     (let ((error-str (format nil "~A" e)))
                       (if (or (search "Broken pipe" error-str)
                               (search "closed" error-str)
                               (search "reset" error-str))
                           ;; Connection error, exit gracefully
                           (progn
                             (log-message "Client ~A connection lost" char-name)
                             (return))
                           ;; Other error, log it
                           (progn
                             (log-error "Error in client handler: ~A" e)
                             (return)))))))
      (error (e)
        (log-error "Client handler error for ~A: ~A" char-name e))))

  ;; Cleanup when disconnected
  (let ((session-id (session-id session)))
    (log-message "Attempting to remove thread for session ~A" session-id)
    (remhash session-id *player-threads*)
    (when (session-character session)
      (world-remove-character! world (session-character session)))
    (session-disconnect session)))

(defun accept-connections (world)
  "Accept incoming client connections.
When *server-tls-prefer-start-tls* is true, the START_TLS telnet option
is offered on each connection, allowing clients to upgrade to TLS."
  (handler-case
      (loop while *server-running*
            do
            (handler-case
                (let ((client-socket (usocket:socket-accept *server-socket*)))
                  (when client-socket
                    (if (not *server-running*)
                        (usocket:socket-close client-socket)
                        ;; Quick non-telnet guard before any resource allocation
                        (when (telnet:telnet-guard-connection client-socket)
                          (handler-case
                              (let ((session
                                      (if (and *server-tls-prefer-start-tls*
                                               *server-ssl-certificate*
                                               *server-ssl-key*)
                                          (new-telnet-session
                                           client-socket
                                           :start-tls t
                                           :certificate *server-ssl-certificate*
                                           :key *server-ssl-key*
                                           :password *server-ssl-password*)
                                          (new-telnet-session client-socket))))
                                ;; Start session thread
                                (let ((thread (bordeaux-threads:make-thread
                                               (lambda () (handle-client world session))
                                               :name (format nil "session-~A"
                                                             (session-id session)))))
                                  (log-message
                                   "Thread for session ~A created" (session-id session))
                                  (setf (gethash (session-id session) *player-threads*)
                                        thread)))
                            (error (e)
                              ;; Session creation failed — close the socket so it doesn't leak
                              (usocket:socket-close client-socket)
                              (log-error "Failed to create session: ~A" e)))))))
              (usocket:timeout-error ()
                ;; Just a timeout, continue accepting
                nil)
              (error (e)
                ;; If the server is stopping, ignore socket errors from closed listening socket
                (when *server-running*
                  (log-error "Error accepting connection: ~A" e)))))
    (error (e)
      (when *server-running*
        (log-error "Accept connections error: ~A" e)))))

(defun accept-tls-connections (world)
  "Accept incoming TLS-encrypted client connections."
  (handler-case
      (loop while *server-running*
            do
            (handler-case
                (let ((client-socket (usocket:socket-accept *server-tls-socket*)))
                  (when client-socket
                    (if (not *server-running*)
                        (usocket:socket-close client-socket)
                        (progn
                          (log-message "New TLS connection accepted")
                          (let ((session
                                  (handler-case
                                      (new-telnet-tls-session
                                       client-socket
                                       :certificate *server-ssl-certificate*
                                       :key *server-ssl-key*
                                       :password *server-ssl-password*)
                                    (telnet:telnet-tls-error (e)
                                      (log-error
                                       "TLS handshake failed: ~A"
                                       (telnet:telnet-error-message e))
                                      (usocket:socket-close client-socket)
                                      nil)
                                    (error (e)
                                      ;; Any other error — close socket so it doesn't leak
                                      (log-error
                                       "Failed to create TLS session: ~A" e)
                                      (usocket:socket-close client-socket)
                                      nil))))
                            (when session
                              (let ((thread
                                      (bordeaux-threads:make-thread
                                       (lambda () (handle-client world session))
                                       :name (format nil "session-tls-~A"
                                                     (session-id session)))))
                                (log-message
                                 "Thread for TLS session ~A created"
                                 (session-id session))
                                (setf (gethash (session-id session)
                                              *player-threads*)
                                      thread))))))))
              (usocket:timeout-error ()
                nil)
              (error (e)
                (when *server-running*
                  (log-error
                   "Error accepting TLS connection: ~A" e)))))
    (error (e)
      (when *server-running*
        (log-error "Accept TLS connections error: ~A" e)))))

(defun start-mud-server (&key (host *server-host*) (port *server-port*)
                           force-new
                           (tls-port *server-tls-port*)
                           (tls-certificate *server-ssl-certificate*)
                           (tls-key *server-ssl-key*)
                           (prefer-start-tls *server-tls-prefer-start-tls*))
  "Start the MUD server.

HOST and PORT configure the plain-text telnet listener.
When TLS-CERTIFICATE and TLS-KEY are provided, a TLS listener is also
started on TLS-PORT (default 992).  The TLS listener provides immediate
TLS encryption (SSL_accept before any telnet negotiation).

When PREFER-START-TLS is true (the default), the START_TLS telnet option
(46) is offered on the plain-text port, allowing clients to upgrade the
connection to TLS in-band."
  (bordeaux-threads:with-lock-held (*server-lock*)
    (if *server-running*
        (progn
          (log-error "Server is already running!")
          (return-from start-mud-server nil))
        ;; Initialize world
        (let ((world (world-restore-or-initialize :force-new force-new
                                                  :initializer #'apeiron.worlds:new-default-world)))
          ;; Start event logging to file
          (start-event-logging :log-file (merge-pathnames "events.log" *data-directory*))
          ;; Start plain-text listener
          (setf *server-socket*
                (usocket:socket-listen host port :reuse-address t :backlog 5))
          (setf *server-running* t)
          (log-message "MUD Server started on ~A:~D" host port)

          ;; Start TLS listener (if certificate configured)
          (when (and tls-certificate tls-key)
            (handler-case
                (progn
                  (setf *server-tls-socket*
                        (usocket:socket-listen host tls-port
                                               :reuse-address t :backlog 5))
                  (log-message "TLS listener started on ~A:~D" host tls-port)
                  (setf *tls-acceptance-thread*
                        (bordeaux-threads:make-thread
                         (lambda () (accept-tls-connections world))
                         :name "accept-tls-connections")))
              (error (e)
                (log-error "Failed to start TLS listener: ~A" e))))

          ;; Start plain-text acceptance thread
          (setf *acceptance-thread*
                (bordeaux-threads:make-thread
                 (lambda () (accept-connections world))
                 :name "accept-connections"))

          ;; Signal whether START_TLS is available
          (when prefer-start-tls
            (log-message
             "START_TLS option (46) enabled on plain-text port"))
          t))))

(defun stop-mud-server ()
  "Stop the MUD server, including any TLS listener."
  (bordeaux-threads:with-lock-held (*server-lock*)
    (when *server-running*
      (setf *server-running* nil)

      ;; Fire dummy connections to unblock socket-accept on both sockets
      (flet ((unblock (socket)
               (when socket
                 (handler-case
                     (let ((port (usocket:get-local-port socket)))
                       (when port
                         (let ((dummy (usocket:socket-connect "127.0.0.1" port)))
                           (usocket:socket-close dummy))))
                   (error () nil)))))
        (unblock *server-socket*)
        (unblock *server-tls-socket*))

      ;; Close TLS server socket
      (when *server-tls-socket*
        (handler-case
            (usocket:socket-close *server-tls-socket*)
          (error (e)
            (log-error "Error closing TLS socket: ~A" e)))
        (setf *server-tls-socket* nil))

      ;; Close plain server socket
      (when *server-socket*
        (handler-case
            (usocket:socket-close *server-socket*)
          (error (e)
            (log-error "Error closing server socket: ~A" e)))
        (setf *server-socket* nil))

      ;; Wait for TLS acceptance thread to exit
      (when *tls-acceptance-thread*
        (handler-case
            (bordeaux-threads:join-thread *tls-acceptance-thread*)
          (error (e)
            (log-error "Error joining TLS acceptance thread: ~A" e)))
        (setf *tls-acceptance-thread* nil))

      ;; Wait for plain-text acceptance thread to exit
      (when *acceptance-thread*
        (handler-case
            (bordeaux-threads:join-thread *acceptance-thread*)
          (error (e)
            (log-error "Error joining acceptance thread: ~A" e)))
        (setf *acceptance-thread* nil))

      ;; Disconnect all players
      (let ((world (get-persistent-world)))
        (dolist (player (characters world))
          (world-remove-character! world player)
          (session-disconnect (character-session player))))

      ;; Stop event logging
      (stop-event-logging)
      (log-message "MUD Server stopped")
      t)))

(defun get-server-status ()
  "Get the current status of the server."
  (let ((world (get-persistent-world)))
    (format nil "Server running: ~A~%Players online: ~D~%Rooms in world: ~D~%"
            (if *server-running*
                "Yes"
                "No")
            (world-total-players world) (world-total-rooms world))))
