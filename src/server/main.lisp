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

(defvar *server-start-time* nil
  "Universal time when the server was started, used for uptime calculations.")

(defun %make-mssp-info-fn (world)
  "Return a function of no arguments that produces an MSSP variable alist
for the given WORLD: NAME, PLAYERS, and UPTIME."
  (lambda ()
    (let ((vars (list (cons "NAME" *mud-name*)
                      (cons "PLAYERS" (princ-to-string (world-total-characters world)))
                      (cons "UPTIME" (princ-to-string *server-start-time*)))))
      (log-message "[MSSP] mssp-info-fn called: returning ~D vars (NAME=~S PLAYERS=~S UPTIME=~S)"
                   (length vars) *mud-name* (world-total-characters world)
                   (floor (- (get-universal-time) *server-start-time*)))
      vars)))

(defun %client-login-flow (session)
  "Present the login prompt and dispatch to the appropriate flow.
Returns (values character account) where ACCOUNT is NIL for guests."
  (let ((choice (string-downcase
                 (string-trim '(#\Space #\Tab)
                              (ask-input session
                                         (format nil "~A (n)ew, (g)uest, or (c)onnect?"
                                                 (bright-white "Choose:")))))))
    (cond
      ((or (string= choice "n") (string= choice "new"))
       (%client-register-flow session))
      ((or (string= choice "g") (string= choice "guest"))
       (%client-guest-flow session))
      ((or (string= choice "c") (string= choice "connect"))
       (%client-connect-flow session))
      (t
       (mud-write session (format nil "Invalid choice: ~A" choice))
       (%client-login-flow session)))))

(defun %client-register-flow (session)
  "Handle new account registration flow.
Returns (values character account)."
  (let* ((account-name (ask-input session "Choose an account name:"))
         (account-password (ask-input session "Choose a password:" :secret t))
         (account-email (ask-input session "Email (optional, for password reset):")))
    (handler-case
        (let ((account (register-account account-name account-password
                                         :email (unless (zerop (length account-email))
                                                  account-email))))
          (mud-write session (format nil "Account ~A created successfully!" (bright-green account-name)))
          (let* ((char-name (ask-input session "Choose a character name:" :default account-name))
                 (character (new-character char-name session :owner (account-name account))))
            (values character account)))
      (error (e)
        (mud-write session (format nil "~A" e))
        (%client-register-flow session)))))

(defun %client-guest-flow (session)
  "Handle guest login flow.
Returns (values character nil)."
  (let* ((guest-name (format nil "Guest~D" (random 10000)))
         (char-name (ask-input session "What is your name?" :default guest-name))
         (character (new-character char-name session)))
    (values character nil)))

(defun %client-connect-flow (session)
  "Handle existing account authentication flow.
Returns (values character account)."
  (let* ((account-name (ask-input session "Account name:"))
         (account-password (ask-input session "Password:" :secret t))
         (account (authenticate-account account-name account-password)))
    (if account
        (let* ((world (apeiron.persistence:get-persistent-world))
               (existing-char (find-character-by-owner world (account-name account))))
          (mud-write session (format nil "Welcome back, ~A!" (bright-green (account-name account))))
          (if existing-char
              (progn
                (mud-write session (format nil "Reconnecting to your character, ~A." (bright-green (object-name existing-char))))
                ;; Clear the OLD session's back-reference BEFORE linking the new
                ;; session.  This prevents a race where the old thread's cleanup
                ;; (in handle-client) would see (session-character old-session)
                ;; still pointing to existing-char, then wipe (character-session
                ;; existing-char) = nil and call world-remove-character! on the
                ;; character — leaving it in the room with NIL session.
                (let ((old-session (character-session existing-char)))
                  (when old-session
                    (setf (session-character old-session) nil)))
                ;; Re-link session to existing character
                (setf (character-session existing-char) session
                      (session-character session) existing-char)
                (values existing-char account))
              ;; No existing character — create one
              (let* ((char-name (ask-input session "Choose a character name:" :default (account-name account)))
                     (character (new-character char-name session :owner (account-name account))))
                (values character account))))
        (progn
          (mud-write session "Invalid account name or password.")
          (%client-connect-flow session)))))

(defun handle-client (world session)
  "Main loop for handling a client connection."
  (let* ((telnet-conn (and (typep session 'telnet-session)
                           (session-telnet-connection session)))
         (session-id (session-id session))
         (remote-addr (and (typep session 'telnet-session)
                           (session-remote-address session))))
    ;; Drain pending telnet negotiation (MSSP, etc.) BEFORE the
    ;; login prompt, so the MSSP response is sent immediately
    ;; after the client's data arrives.
    (when telnet-conn
      (%drain-telnet-negotiation telnet-conn))

    ;; ─── Login phase ────────────────────────────────────────────────
    (multiple-value-bind (character account)
        (%client-login-flow session)
      (declare (ignore account))

      ;; Register character in the world.  CREATE-OBJECT! handles
      ;; materialization on persistent worlds and skips already-persistent
      ;; objects (reconnected characters).  Then place in the starting room.
      (create-object! world character)
      (place-character! world character)
      (mud-write session (object-describe (object-location character)))
      (mud-write session "Welcome to the MUD!")

      (let ((char-name (object-name character)))
        (let ((ndc (format nil "ip=~A session=~A char=~A"
                           remote-addr session-id char-name)))
          (log:with-ndc (ndc)
            (log-message "New connection: ~A~:[ (guest)~; (account: ~A)~]"
                         char-name
                         (character-owner character)
                         (character-owner character))

            ;; ─── Game loop ────────────────────────────────────────────────
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
                (log-error "Client handler error for ~A: ~A" char-name e)))))))

    ;; Cleanup when disconnected
    (log-message "Attempting to remove thread for session ~A" session-id)
    (let ((character (session-character session)))
      (when character
        ;; Clear session links first — this prevents stop-mud-server
        ;; Clear session links before world-remove-character! —
        ;; this prevents stop-mud-server from racing to process
        ;; the same character via (characters world).
        (setf (session-character session) nil
              (character-session character) nil)
        (world-remove-character! world character)))
    ;; Remove from tracking AFTER cleanup so stop-mud-server joins
    ;; this thread before processing characters.
    (remhash session-id *player-threads*)
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
                                         :password *server-ssl-password*
                                         :mssp-info-fn (%make-mssp-info-fn world))
                                        (new-telnet-session
                                         client-socket
                                         :mssp-info-fn (%make-mssp-info-fn world)))))
                              ;; Session may be NIL if rejected as non-telnet
                              (when session
                                (let ((thread
                                        (bordeaux-threads:make-thread
                                         (lambda ()
                                           (handle-client world session))
                                         :name
                                         (format nil "session-~A"
                                                 (session-id session)))))
                                  (log-message
                                   "Thread for session ~A created"
                                   (session-id session))
                                  (setf (gethash (session-id session)
                                                 *player-threads*)
                                        thread))))
                          (error (e)
                            (usocket:socket-close client-socket)
                            (log-error "Failed to create session: ~A" e))))))
              (usocket:timeout-error ()
                nil)
              (error (e)
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
                        (let ((mssp-fn (%make-mssp-info-fn world)))
                          (log-message "New TLS connection accepted")
                          (let ((session
                                  (handler-case
                                      (new-telnet-tls-session
                                       client-socket
                                       :certificate *server-ssl-certificate*
                                       :key *server-ssl-key*
                                       :password *server-ssl-password*
                                       :mssp-info-fn mssp-fn)
                                    (telnet:telnet-tls-error (e)
                                      (log-error
                                       "TLS handshake failed: ~A"
                                       (telnet:telnet-error-message e))
                                      (usocket:socket-close client-socket)
                                      nil)
                                    (error (e)
                                      (log-error
                                       "Failed to create TLS session: ~A" e)
                                      (usocket:socket-close client-socket)
                                      nil))))
                            (when session
                              (let ((thread
                                      (bordeaux-threads:make-thread
                                       (lambda ()
                                         (handle-client world session))
                                       :name
                                       (format nil "session-tls-~A"
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
          (configure-logging)
          ;; Start plain-text listener
          (setf *server-socket*
                (usocket:socket-listen host port :reuse-address t :backlog 5))
          (setf *server-running* t
                *server-start-time* (get-universal-time))
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
      (setf *server-running* nil
            *server-start-time* nil)

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

      ;; Wait for all player threads to finish their cleanup before
      ;; we touch any characters — avoids racing with handle-client.
      (maphash (lambda (id thread)
                 (declare (ignore id))
                 (handler-case
                     (bordeaux-threads:join-thread thread)
                   (error (e)
                     (log-error "Error joining player thread: ~A" e))))
               *player-threads*)
      (clrhash *player-threads*)

      ;; Disconnect all remaining characters (safety net)
      (let ((world (get-persistent-world)))
        (dolist (character (characters world))
          (let ((session (character-session character)))
            (world-remove-character! world character)
            (when session
              (session-disconnect session)))))

      ;; Stop event logging
      (shutdown-logging)
      (log-message "MUD Server stopped")
      t)))

(defun get-server-status ()
  "Get the current status of the server."
  (let ((world (get-persistent-world)))
    (format nil "Server running: ~A~%Characters online: ~D~%Rooms in world: ~D~%"
            (if *server-running*
                "Yes"
                "No")
            (world-total-characters world) (world-total-rooms world))))
