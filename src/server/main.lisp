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

(defun %login-ask (session question &key (default "") secret)
  "Ask a question during the login flow, keeping the connection alive.

Wraps ASK-INPUT: reads with a 30-second poll (same cadence as the game
loop's keepalive; secrets keep the 300s limit), and when the read times
out because the client is idle but connected, sends a NOP keepalive
(SESSION-KEEPALIVE) and asks again, so idle login connections are not
dropped.  When the client is gone (:EOF / :CONNECTION-LOST) returns
:ABORT instead of looping forever.

Returns (values ANSWER STATUS).  STATUS is NIL on success, or :ABORT
when the client connection is gone and the flow must end."
  (loop
    (multiple-value-bind (answer status)
        (ask-input session question :default default :secret secret
                   :timeout (if secret 300 30))
      (cond
        ((null status)
         (return (values answer nil)))
        ((eq status :timeout)
         ;; Idle but connected — NOP keepalive, then ask again.
         (handler-case (session-keepalive session) (error () nil)))
        (t
         (return (values nil :abort)))))))

(defun %client-login-flow (session)
  "Present the login prompt and dispatch to the appropriate flow.
Returns (values character account) where ACCOUNT is NIL for guests,
or (values NIL NIL) when the client disconnected before logging in.

This is an explicit LOOP, not a tail-recursion: a client that drops the
connection at the prompt must not keep the session thread spinning (and
allocating) forever.  Idle-but-connected clients are kept alive via
%LOGIN-ASK's keepalive and re-prompted."
  (loop
    (multiple-value-bind (choice status)
        (%login-ask session
                    (format nil "~A (n)ew, (g)uest, or (c)onnect?"
                            (bright-white "Choose:")))
      (when (eq status :abort)
        (return (values nil nil)))
      (let ((choice (string-downcase (string-trim '(#\Space #\Tab) choice))))
        (cond
          ((or (string= choice "n") (string= choice "new"))
           (return (%client-register-flow session)))
          ((or (string= choice "g") (string= choice "guest"))
           (return (%client-guest-flow session)))
          ((or (string= choice "c") (string= choice "connect"))
           (return (%client-connect-flow session)))
          (t
           (mud-write session (format nil "Invalid choice: ~A" choice))))))))

(defun %client-register-flow (session)
  "Handle new account registration flow.
Returns (values character account), or (values NIL NIL) when the client
disconnected during the flow."
  (loop
    (multiple-value-bind (account-name name-status)
        (%login-ask session "Choose an account name:")
      (when (eq name-status :abort)
        (return (values nil nil)))
      (multiple-value-bind (account-password password-status)
          (%login-ask session "Choose a password:" :secret t)
        (when (eq password-status :abort)
          (return (values nil nil)))
        (multiple-value-bind (account-email email-status)
            (%login-ask session "Email (optional, for password reset):")
          (when (eq email-status :abort)
            (return (values nil nil)))
          (handler-case
              (let ((account (register-account account-name account-password
                                               :email (unless (zerop (length account-email))
                                                        account-email))))
                (mud-write session (format nil "Account ~A created successfully!" (bright-green account-name)))
                (multiple-value-bind (char-name char-status)
                    (%login-ask session "Choose a character name:" :default account-name)
                  (when (eq char-status :abort)
                    (return (values nil nil)))
                  (let ((character (new-character char-name session :account (account-name account))))
                    (return (values character account)))))
            (error (e)
              (mud-write session (format nil "~A" e)))))))))

(defun %client-guest-flow (session)
  "Handle guest login flow.
Returns (values character nil), or (values NIL NIL) when the client
disconnected during the flow."
  (let* ((guest-name (format nil "Guest~D" (random 10000))))
    (multiple-value-bind (char-name status)
        (%login-ask session "What is your name?" :default guest-name)
      (if (eq status :abort)
          (values nil nil)
          (values (new-character char-name session) nil)))))

(defun %client-connect-flow (session)
  "Handle existing account authentication flow.
Returns (values character account), or (values NIL NIL) when the client
disconnected during the flow."
  (loop
    (multiple-value-bind (account-name name-status)
        (%login-ask session "Account name:")
      (when (eq name-status :abort)
        (return (values nil nil)))
      (multiple-value-bind (account-password password-status)
          (%login-ask session "Password:" :secret t)
        (when (eq password-status :abort)
          (return (values nil nil)))
        (let ((account (authenticate-account account-name account-password)))
          (if account
              (let* ((world (apeiron.persistence:get-persistent-world))
                     (existing-char (find-character-by-account world (account-name account))))
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
                      (return (values existing-char account)))
                    ;; No existing character — create one
                    (multiple-value-bind (char-name char-status)
                        (%login-ask session "Choose a character name:" :default (account-name account))
                      (when (eq char-status :abort)
                        (return (values nil nil)))
                      (let ((character (new-character char-name session :account (account-name account))))
                        (return (values character account))))))
              (mud-write session "Invalid account name or password.")))))))

(defun handle-client (world session)
  "Main loop for handling a client connection."
  (let* ((telnet-conn (and (typep session 'telnet-session)
                           (session-telnet-connection session)))
         (session-id (session-id session))
         (remote-addr (and (typep session 'telnet-session)
                           (session-remote-address session))))
    (unwind-protect
         (progn
           ;; Drain pending telnet negotiation (MSSP, etc.) BEFORE the
           ;; login prompt, so the MSSP response is sent immediately
           ;; after the client's data arrives.
           (when telnet-conn
             (%drain-telnet-negotiation telnet-conn))

           ;; ─── Login phase ────────────────────────────────────────────────
           (multiple-value-bind (character account)
               (%client-login-flow session)
             (declare (ignore account))
             (when character
               ;; Register character in the world.  CREATE-OBJECT! handles
               ;; materialization on persistent worlds and skips already-persistent
               ;; objects (reconnected characters).  Then place in the starting room.
               (create-object! world character)
               (place-character! world character)
               (mud-write session (object-long-description (object-location character)))
               (mud-write session "Welcome to the MUD!")
               ;; Push initial character state to protocol-capable clients
               ;; (e.g. GMCP Char.Vitals/Char.Stats).
               (session-sync-character session character)

               (let ((char-name (object-name character)))
                 (let ((ndc (format nil "ip=~A session=~A char=~A"
                                    remote-addr session-id char-name)))
                   (log:with-ndc (ndc)
                     (log-message "New connection: ~A~:[ (guest)~; (account: ~A)~]"
                                  char-name
                                  (character-account character)
                                  (character-account character))

                     ;; ─── Game loop ────────────────────────────────────────
                     (handler-case
                         ;; Stop as soon as the transport is gone (e.g. the
                         ;; player issued QUIT, or the socket dropped).  A
                         ;; closed connection must not be polled again: on a
                         ;; plain fd-stream LISTEN signals a CLOSED-STREAM-ERROR,
                         ;; but on a TLS (cl+ssl) stream it signals a bare
                         ;; TYPE-ERROR while dereferencing the freed SSL
                         ;; handle — which the error clauses below cannot
                         ;; recognise as a disconnect.
                         (loop while (and *server-running*
                                          (session-alive-p session))
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
                                            ((or (eq status :eof)
                                                 (eq status :connection-lost)
                                                 (typep status 'error))
                                             (log-message "Client ~A disconnected ~A" char-name status)
                                             (return))
                                            (line
                                             (let ((trimmed (string-trim '(#\Return #\Newline) line)))
                                               (when (and trimmed (> (length trimmed) 0))
                                                 (process-command world character trimmed)
                                                 ;; Refresh protocol-side character
                                                 ;; state (e.g. GMCP vitals/stats)
                                                 ;; after the command took effect.
                                                 (session-sync-character session character))))
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
                           (log-error "Client handler error for ~A: ~A" char-name e)))))))))
      ;; Cleanup when disconnected — ALWAYS runs, even when the login
      ;; flow bails out on a dead connection or signals an error.
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
      (session-disconnect session))))

(defun %spawn-session-thread (world session &key (thread-name "session")
                              (description "session"))
  "Start the per-client handler thread for SESSION, register it in
*PLAYER-THREADS*, and return the thread.  THREAD-NAME is the thread's
name base (\"session\" or \"session-tls\"); DESCRIPTION is how the
session is referred to in the log."
  (let ((thread
          (bordeaux-threads:make-thread
           (lambda () (handle-client world session))
           :name (format nil "~A-~A" thread-name (session-id session)))))
    (log-message "Thread for ~A ~A created" description (session-id session))
    (setf (gethash (session-id session) *player-threads*) thread)
    thread))

(defun %accept-plain-client (world client-socket &key prefer-start-tls
                             tls-certificate tls-key tls-password)
  "Handle one freshly-accepted plain-text socket: build the telnet
session (offering the START_TLS option when TLS material is configured)
and start its handler thread."
  (handler-case
      (let ((session
              (if (and prefer-start-tls tls-certificate tls-key)
                  (new-telnet-session
                   client-socket
                   :start-tls t
                   :certificate tls-certificate
                   :key tls-key
                   :password tls-password
                   :mssp-info-fn (%make-mssp-info-fn world))
                  (new-telnet-session
                   client-socket
                   :mssp-info-fn (%make-mssp-info-fn world)))))
        ;; Session may be NIL if rejected as non-telnet
        (when session
          (%spawn-session-thread world session)))
    (error (e)
      (usocket:socket-close client-socket)
      (log-error "Failed to create session: ~A" e))))

(defun %accept-tls-client (world client-socket tls-certificate tls-key tls-password)
  "Handle one freshly-accepted TLS socket: run the server-side TLS
handshake, build the telnet session, and start its handler thread.

Returns NIL — after closing CLIENT-SOCKET — when the TLS material is
missing or the handshake fails."
  (when (or (null tls-certificate) (null tls-key))
    ;; Fail loudly and actionably instead of letting OpenSSL hand back
    ;; its opaque "no shared cipher".
    (log-error
     "TLS connection rejected: no certificate/key configured for the TLS listener")
    (usocket:socket-close client-socket)
    (return-from %accept-tls-client nil))
  (log-message "New TLS connection accepted")
  (let ((session
          (handler-case
              (new-telnet-tls-session
               client-socket
               :certificate tls-certificate
               :key tls-key
               :password tls-password
               :mssp-info-fn (%make-mssp-info-fn world))
            (telnet:telnet-tls-error (e)
              (log-error "TLS handshake failed: ~A"
                         (telnet:telnet-error-message e))
              (usocket:socket-close client-socket)
              nil)
            (error (e)
              (log-error "Failed to create TLS session: ~A" e)
              (usocket:socket-close client-socket)
              nil))))
    (when session
      (%spawn-session-thread world session
                             :thread-name "session-tls"
                             :description "TLS session"))))

(defun accept-connections (world &key
                                   (prefer-start-tls *server-tls-prefer-start-tls*)
                                   (tls-certificate *server-ssl-certificate*)
                                   (tls-key *server-ssl-key*)
                                   (tls-password *server-ssl-password*))
  "Accept incoming client connections.
When PREFER-START-TLS is true, the START_TLS telnet option (46) is
offered on each connection, allowing clients to upgrade to TLS using
TLS-CERTIFICATE, TLS-KEY, and TLS-PASSWORD.

The TLS material is captured by the caller at listener-start time
rather than re-read from the package globals for every connection, so a
hot reload (SAFE-UPDATE) that re-evaluates the config DEFVARs can never
strip the running listener of its certificate."
  (handler-case
      (loop while *server-running*
            do
            (handler-case
                (let ((client-socket (usocket:socket-accept *server-socket*)))
                  (when client-socket
                    (if *server-running*
                        (%accept-plain-client
                         world client-socket
                         :prefer-start-tls prefer-start-tls
                         :tls-certificate tls-certificate
                         :tls-key tls-key
                         :tls-password tls-password)
                        (usocket:socket-close client-socket))))
              (usocket:timeout-error ()
                nil)
              (error (e)
                (when *server-running*
                  (log-error "Error accepting connection: ~A" e)))))
    (error (e)
      (when *server-running*
        (log-error "Accept connections error: ~A" e)))))

(defun accept-tls-connections (world &key
                                     (tls-certificate *server-ssl-certificate*)
                                     (tls-key *server-ssl-key*)
                                     (tls-password *server-ssl-password*))
  "Accept incoming TLS-encrypted client connections.

TLS-CERTIFICATE, TLS-KEY, and TLS-PASSWORD are captured by the caller
at listener-start time rather than re-read from the package globals for
every connection, so a hot reload (SAFE-UPDATE) that re-evaluates the
config DEFVARs cannot leave the running listener with no certificate —
which OpenSSL reports as the opaque 'no shared cipher'."
  (handler-case
      (loop while *server-running*
            do
            (handler-case
                (let ((client-socket (usocket:socket-accept *server-tls-socket*)))
                  (when client-socket
                    (if *server-running*
                        (%accept-tls-client
                         world client-socket tls-certificate tls-key tls-password)
                        (usocket:socket-close client-socket))))
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

          ;; Start TLS listener (if certificate configured).
          ;; Mirror the effective TLS material into the package globals
          ;; (for introspection and for tests that reset them), but the
          ;; accept loops capture it as arguments, so the keyword-argument
          ;; API works exactly like setting *server-ssl-certificate* etc.
          ;; before starting (run-mud.lisp does the latter).  Without this
          ;; binding, a server started via
          ;;   (start-mud-server :tls-certificate "c.pem" :tls-key "k.pem")
          ;; would accept TLS connections but run SSL_accept with NO
          ;; certificate, failing every handshake.
          (when (and tls-certificate tls-key)
            (setf *server-ssl-certificate* tls-certificate
                  *server-ssl-key* tls-key)
            (handler-case
                (progn
                  (setf *server-tls-socket*
                        (usocket:socket-listen host tls-port
                                               :reuse-address t :backlog 5))
                  (log-message "TLS listener started on ~A:~D" host tls-port)
                  (setf *tls-acceptance-thread*
                        (bordeaux-threads:make-thread
                         (lambda ()
                           (accept-tls-connections
                            world
                            :tls-certificate tls-certificate
                            :tls-key tls-key
                            :tls-password *server-ssl-password*))
                         :name "accept-tls-connections")))
              (error (e)
                (log-error "Failed to start TLS listener: ~A" e))))

          ;; Start plain-text acceptance thread.  Capture the TLS material
          ;; too: START_TLS handshakes use it, and the captured values keep
          ;; the live listener immune to later hot reloads.
          (setf *acceptance-thread*
                (bordeaux-threads:make-thread
                 (lambda ()
                   (accept-connections
                    world
                    :prefer-start-tls prefer-start-tls
                    :tls-certificate tls-certificate
                    :tls-key tls-key
                    :tls-password *server-ssl-password*))
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
