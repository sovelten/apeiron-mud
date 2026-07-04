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
           
           ;; Server should ask for name (telnet-read-line strips IAC negotiation)
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
           
           ;; Verify player exists in the world
           (let* ((world (apeiron.persistence:get-persistent-world))
                  (player (loop for p being the hash-values of (apeiron.core:world-players world)
                               when (equal (apeiron.core:object-name p) "QuitTestPlayer")
                                 return p)))
             (is (not (null player)))
             
             ;; Now send "quit"
             (telnet:telnet-write-string client-conn "quit")
             
             ;; Server should send "Goodbye!"
             (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
               (declare (ignore status))
               (is (string= line "Goodbye!")))
             
             ;; Wait for session thread to cleanup
             (sleep 0.5)
             
             ;; Verify player is removed from the world
             (is (not (gethash (apeiron.core:object-id player) (apeiron.core:world-players world))))))
      ;; Cleanup
      (when client-conn (telnet:telnet-connection-close client-conn))
      (when client-socket (usocket:socket-close client-socket))
      (apeiron.server:stop-mud-server))))

(test player-contextual-eval
  "Test evaluation of (me) command, returning the player character"
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

           ;; Server should ask for name (telnet-read-line strips IAC negotiation)
           (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
             (is (not (null line)))
             (is (equal line "What is your name?")))

           ;; Send player name
           (telnet:telnet-write-string client-conn "TestPlayer")

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

           ;; Verify player interactions
           (let* ((world (apeiron.persistence:get-persistent-world))
                  (player (loop for p being the hash-values of (apeiron.core:world-players world)
                                when (equal (apeiron.core:object-name p) "TestPlayer")
                                  return p)))
             (is (not (null player)))

             ;; Now send eval
             (telnet:telnet-write-string client-conn "eval (object-name (me))")

             ;; Server should respond with player name
             (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
               (declare (ignore status))
               (is (string= line "TestPlayer")))

             ;; Consume prompt before next command
             (let ((prompt-char nil))
               (setf prompt-char (telnet:telnet-read-char client-conn :timeout 2))
               (is (char= prompt-char #\>))
               (setf prompt-char (telnet:telnet-read-char client-conn :timeout 2))
               (is (char= prompt-char #\Space)))

             ;; (here) should bind to current location
             (telnet:telnet-write-string client-conn "eval (object-name (here))")

             ;; Server should respond with player location name
             (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
               (declare (ignore status))
               (is (string= line (object-name (object-location player)))))))

      ;; Cleanup
      (when client-conn (telnet:telnet-connection-close client-conn))
      (when client-socket (usocket:socket-close client-socket))
      (apeiron.server:stop-mud-server))))

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
           
           ;; Server should ask for name
           (multiple-value-bind (line status) (telnet:telnet-read-line client-conn :timeout 5)
             (is (not (null line)))
             (is (equal line "What is your name?")))
           
           ;; Send player name
           (telnet:telnet-write-string client-conn "AbruptPlayer")
           
           (sleep 0.3)
           
           ;; Verify player is in world
           (let* ((world (apeiron.persistence:get-persistent-world))
                  (player (loop for p being the hash-values of (apeiron.core:world-players world)
                                when (equal (apeiron.core:object-name p) "AbruptPlayer")
                                  return p)))
             (is (not (null player)))
             
             ;; Now close client connection abruptly without quitting!
             (telnet:telnet-connection-close client-conn)
             (usocket:socket-close client-socket)
             (setf client-conn nil
                   client-socket nil)
             
             ;; Wait for server loop to detect EOF / socket error and run cleanup
             (sleep 0.5)
             
             ;; Verify player is cleaned up from the world
             (is (not (gethash (apeiron.core:object-id player) (apeiron.core:world-players world))))))
      ;; Cleanup
      (when client-conn (telnet:telnet-connection-close client-conn))
      (when client-socket (usocket:socket-close client-socket))
      (apeiron.server:stop-mud-server))))
