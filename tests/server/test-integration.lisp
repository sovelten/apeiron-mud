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
