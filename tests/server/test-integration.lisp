(in-package #:apeiron-test)

(in-suite server-suite)

(test network-quit-command-integration
  "Test a real client connecting, naming themselves, and executing the quit command."
  (apeiron.server:stop-mud-server)
  (is (apeiron.server:start-mud-server :host "127.0.0.1" :port 0))
  (let* ((port (usocket:get-local-port apeiron.server:*server-socket*))
         (client-socket nil)
         (client-conn nil))
    (unwind-protect
         (progn
           ;; Connect client using telnet-aware connection
           (setf client-socket (usocket:socket-connect "127.0.0.1" port))
           (setf client-conn (telnet:make-telnet-connection client-socket))
           
           ;; Wait a moment for connection to establish and negotiation to complete
           (sleep 0.5)
           
           ;; Server should present login prompt
           (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
             (is (not (null line)))
             (is (search "Choose:" line)))
           
           ;; Choose guest
           (telnet:telnet-write-string client-conn "g")
           
           ;; Server should ask for name
           (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
             (is (not (null line)))
             (is (equal line "What is your name?")))
           
           ;; Send player name
           (telnet:telnet-write-string client-conn "QuitTestPlayer")
           
           ;; Server should create character and send room description and greeting
           (sleep 0.2)
           ;; Read until we see the "Welcome to the MUD!" greeting
           (let ((greeting-found nil))
             (loop
               (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 1)
                 (unless line (return))
                 (when (search "Welcome" line)
                   (setf greeting-found t)
                   (return))))
             (is (not (null greeting-found))))
           
           ;; Read next prompt "> "
           (let ((prompt-char nil))
             (setf prompt-char (telnet:telnet-read-char client-conn :timeout 2))
             (is (char= prompt-char #\>))
             (setf prompt-char (telnet:telnet-read-char client-conn :timeout 2))
             (is (char= prompt-char #\Space)))
           
           ;; Verify character exists in the world
           (let* ((world (apeiron.persistence:get-persistent-world))
                  (character (loop for p being the hash-values of (apeiron.core:world-characters world)
                               when (equal (apeiron.core:object-name p) "QuitTestPlayer")
                                 return p)))
             (is (not (null character)))

             ;; Save the character's ID before quit — the quit command
             ;; destroys the BKNR object for guest characters, so slot
             ;; access afterward would fail.
             (let ((char-id (apeiron.core:object-id character)))
               ;; Now send "quit"
               (telnet:telnet-write-string client-conn "quit")

               ;; Server should send "Goodbye!"
               (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
                 (declare (ignore status))
                 (is (string= line "Goodbye!")))

               ;; Wait for session thread to cleanup
               (sleep 0.5)

               ;; Verify character is removed from the world
               (is (not (gethash char-id (apeiron.core:world-characters world)))))))
      ;; Cleanup
      (when client-conn (telnet:telnet-connection-close client-conn))
      (when client-socket (usocket:socket-close client-socket))
      (apeiron.server:stop-mud-server))))

(test character-contextual-eval
  "Test evaluation of (me) command, returning the player character.
The player connects via an admin account, which is required for the
eval command (or wearing a wizard hat)."
  (apeiron.server:stop-mud-server)
  ;; Register a fresh admin account — eval requires admin or a wizard hat.
  ;; Unique names keep the connect flow deterministic across runs.
  (let ((admin-name (format nil "EvalTestAdmin~D" (random 100000)))
        (char-name (format nil "TestCharacter~D" (random 100000))))
    (register-account admin-name "password" :admin t)
    (is (apeiron.server:start-mud-server :host "127.0.0.1" :port 0))
    (let* ((port (usocket:get-local-port apeiron.server:*server-socket*))
           (client-socket nil)
           (client-conn nil))
      (unwind-protect
           (progn
             ;; Connect client using telnet-aware connection
             (setf client-socket (usocket:socket-connect "127.0.0.1" port))
             (setf client-conn (telnet:make-telnet-connection client-socket))

             ;; Wait a moment for connection to establish and negotiation to complete
             (sleep 0.5)

             ;; Server should present login prompt
             (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
               (is (not (null line)))
               (is (search "Choose:" line)))

             ;; Choose connect (existing account)
             (telnet:telnet-write-string client-conn "c")

             ;; Account name
             (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
               (is (not (null line)))
               (is (search "Account name" line)))
             (telnet:telnet-write-string client-conn admin-name)

             ;; Password
             (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
               (is (not (null line)))
               (is (search "Password" line)))
             (telnet:telnet-write-string client-conn "password")

             ;; The secret input echoes '*' per character; skip lines until
             ;; the server welcomes the account back, then it asks for a
             ;; character name (no character exists for this account yet).
             (let ((welcome-found nil))
               (loop
                 (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
                   (declare (ignore status))
                   (unless line (return))
                   (when (search "Welcome back" line)
                     (setf welcome-found t)
                     (return))))
               (is (not (null welcome-found))))
             (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
               (is (not (null line)))
               (is (search "character name" line)))

             ;; Send character name
             (telnet:telnet-write-string client-conn char-name)

             ;; Server should create character and send room description and greeting
             (sleep 0.2)
             ;; Read until we see the "Welcome to the MUD!" greeting
             (let ((greeting-found nil))
               (loop
                 (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 1)
                   (unless line (return))
                   (when (search "Welcome" line)
                     (setf greeting-found t)
                     (return))))
               (is (not (null greeting-found))))

             ;; Read next prompt "> "
             (let ((prompt-char nil))
               (setf prompt-char (telnet:telnet-read-char client-conn :timeout 2))
               (is (char= prompt-char #\>))
               (setf prompt-char (telnet:telnet-read-char client-conn :timeout 2))
               (is (char= prompt-char #\Space)))

             ;; Verify character interactions
             (let* ((world (apeiron.persistence:get-persistent-world))
                    (character (loop for p being the hash-values of (apeiron.core:world-characters world)
                                  when (equal (apeiron.core:object-name p) char-name)
                                    return p)))
               (is (not (null character)))

               ;; Now send eval
               (telnet:telnet-write-string client-conn "eval (object-name (me))")

               ;; Server should respond with character name
               (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
                 (declare (ignore status))
                 (is (string= line char-name)))

               ;; Consume prompt before next command
               (let ((prompt-char nil))
                 (setf prompt-char (telnet:telnet-read-char client-conn :timeout 2))
                 (is (char= prompt-char #\>))
                 (setf prompt-char (telnet:telnet-read-char client-conn :timeout 2))
                 (is (char= prompt-char #\Space)))

               ;; (here) should bind to current location
               (telnet:telnet-write-string client-conn "eval (object-name (here))")

               ;; Server should respond with character location name
               (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
                 (declare (ignore status))
                 (is (string= line (object-name (object-location character)))))))

        ;; Cleanup
        (when client-conn (telnet:telnet-connection-close client-conn))
        (when client-socket (usocket:socket-close client-socket))
        (apeiron.server:stop-mud-server)))))

(test network-unexpected-disconnect-integration
  "Test a real client connecting, naming themselves, and abruptly disconnecting."
  (apeiron.server:stop-mud-server)
  (is (apeiron.server:start-mud-server :host "127.0.0.1" :port 0))
  (let* ((port (usocket:get-local-port apeiron.server:*server-socket*))
         (client-socket nil)
         (client-conn nil))
    (unwind-protect
         (progn
           ;; Connect client using telnet-aware connection
           (setf client-socket (usocket:socket-connect "127.0.0.1" port))
           (setf client-conn (telnet:make-telnet-connection client-socket))
           
           (sleep 0.5)
           
           ;; Server should present login prompt
           (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
             (is (not (null line)))
             (is (search "Choose:" line)))
           
           ;; Choose guest
           (telnet:telnet-write-string client-conn "g")
           
           ;; Server should ask for name
           (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
             (is (not (null line)))
             (is (equal line "What is your name?")))
           
           ;; Send character name
           (telnet:telnet-write-string client-conn "AbruptCharacter")
           
           (sleep 0.3)
           
           ;; Verify character is in world
           (let* ((world (apeiron.persistence:get-persistent-world))
                  (character (loop for p being the hash-values of (apeiron.core:world-characters world)
                                when (equal (apeiron.core:object-name p) "AbruptCharacter")
                                  return p)))
             (is (not (null character)))

             ;; Save ID before disconnect — the cleanup destroys the
             ;; BKNR object for guest characters.
             (let ((char-id (apeiron.core:object-id character)))
               ;; Now close client connection abruptly without quitting!
               (telnet:telnet-connection-close client-conn)
               (usocket:socket-close client-socket)
               (setf client-conn nil
                     client-socket nil)

               ;; Wait for server loop to detect EOF / socket error and run cleanup
               (sleep 0.5)

               ;; Verify character is cleaned up from the world
               (is (not (gethash char-id (apeiron.core:world-characters world)))))))
      ;; Cleanup
      (when client-conn (telnet:telnet-connection-close client-conn))
      (when client-socket (usocket:socket-close client-socket))
      (apeiron.server:stop-mud-server))))

(defun %make-tls-cert (temp-dir)
  "Generate a throwaway self-signed cert+key pair with openssl.
Returns (values cert-path key-path), or signals an error if openssl
is not available.  Tests that need TLS must call this."
  (let* ((cert-path (merge-pathnames "cert.pem" temp-dir))
         (key-path (merge-pathnames "key.pem" temp-dir)))
    (ensure-directories-exist temp-dir)
    (multiple-value-bind (stdout stderr exit)
        (uiop:run-program
         (list "openssl" "req" "-x509"
               "-newkey" "rsa:2048"
               "-keyout" (namestring key-path)
               "-out" (namestring cert-path)
               "-days" "1"
               "-nodes"
               "-subj" "/CN=localhost/O=MUD-Test")
         :output nil
         :ignore-error-status t)
      (declare (ignore stdout stderr))
      (unless (= exit 0)
        (error "openssl cert generation failed with exit ~A" exit))
      (values (namestring cert-path) (namestring key-path)))))

(defun %make-tls-client-connection (tls-port)
  "Connect a TLS client to TLS-PORT and wrap it in a telnet-connection.
The returned connection speaks RFC 854 telnet over an encrypted
cl+ssl client stream — the same setup a real MUD client (tintin++,
Mudlet) uses for direct-TLS connections.  Returns (values conn
client-socket ssl-stream)."
  (let* ((client-socket (usocket:socket-connect "127.0.0.1" tls-port))
         (ssl-stream (cl+ssl:make-ssl-client-stream
                      (usocket:socket-stream client-socket)
                      :verify nil))
         (conn (make-instance 'telnet:telnet-connection
                              :usocket client-socket
                              :raw-stream ssl-stream
                              :protocol (make-instance 'telnet:telnet-protocol))))
    (values conn client-socket ssl-stream)))

(test network-tls-guest-login-integration
  "Full integration over the dedicated TLS port: a real TLS client
connects to the secure listener and can complete the guest login flow.
This exercises accept-tls-connections, the SSL_accept handshake, and
the telnet login prompt — all over an encrypted stream."
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory)
                                    "mud-test-tls-integration/")))
    (unwind-protect
         (progn
           (apeiron.server:stop-mud-server)
           (multiple-value-bind (cert-path key-path)
               (%make-tls-cert temp-dir)
             ;; Exercise the documented keyword-arg API: start-mud-server
             ;; should use the :tls-certificate/:tls-key it was given for
             ;; every accepted connection.  (run-mud.lisp happens to set
             ;; the package globals as well, but the keyword API must not
             ;; silently depend on that.)
             (is (apeiron.server:start-mud-server
                  :host "127.0.0.1" :port 0
                  :tls-port 0
                  :tls-certificate cert-path
                  :tls-key key-path))
             (let* ((tls-port (usocket:get-local-port
                               apeiron.server::*server-tls-socket*))
                    (client-socket nil)
                    (ssl-stream nil)
                    (client-conn nil))
               (unwind-protect
                    (progn
                      ;; Connect a real TLS client
                      (setf (values client-conn client-socket ssl-stream)
                            (%make-tls-client-connection tls-port))
                      (is (not (null client-conn))
                          "TLS client telnet connection created")

                      ;; Wait for handshake + negotiation to settle
                      (sleep 0.5)

                      ;; Server should present the login prompt over TLS
                      (multiple-value-bind (line status)
                          (telnet:telnet-read-line client-conn :timeout 10)
                        (declare (ignore status))
                        (is (not (null line))
                            "Server should send the login prompt over TLS")
                        (when line
                          (is (search "Choose:" line)
                              (format nil "Prompt should say Choose:, got: ~A" line))))

                      ;; Choose guest
                      (telnet:telnet-write-string client-conn "g")

                      ;; Server should ask for a name
                      (multiple-value-bind (line status)
                          (telnet:telnet-read-line client-conn :timeout 10)
                        (declare (ignore status))
                        (is (not (null line)))
                        (when line
                          (is (equal line "What is your name?"))))

                      ;; Send the guest name and expect the greeting
                      (telnet:telnet-write-string client-conn "TlsGuestPlayer")
                      (sleep 0.2)
                      (let ((greeting-found nil))
                        (loop
                          (multiple-value-bind (line status)
                              (telnet:telnet-read-line client-conn :timeout 2)
                            (declare (ignore status))
                            (unless line (return))
                            (when (search "Welcome" line)
                              (setf greeting-found t)
                              (return))))
                        (is (not (null greeting-found))
                            "Guest should be welcomed into the world over TLS")))

                 ;; Cleanup
                 (when client-conn
                   (ignore-errors (telnet:telnet-connection-close client-conn)))
                 (when ssl-stream
                   (ignore-errors (close ssl-stream)))
                 (when client-socket
                   (ignore-errors (usocket:socket-close client-socket)))
                 (apeiron.server:stop-mud-server)
                 ;; Restore the TLS configuration globals so later tests
                 ;; that start the server without TLS args don't inherit
                 ;; this test's cert/key.
                 (setf apeiron.server:*server-ssl-certificate* nil
                       apeiron.server:*server-ssl-key* nil)))))
      (ignore-errors
        (uiop:delete-directory-tree temp-dir
                                    :validate (constantly t)
                                    :if-does-not-exist :ignore)))))
