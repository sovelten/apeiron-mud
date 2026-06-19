(in-package #:mud-test)

(in-suite mud-tests)

(test network-quit-command-integration
  "Test a real client connecting, naming themselves, and executing the quit command."
  (mud:stop-mud-server)
  (is (mud:start-mud-server :host "127.0.0.1" :port 0))
  (let* ((port (usocket:get-local-port mud::*server-socket*))
         (client-socket nil)
         (client-stream nil))
    (unwind-protect
         (progn
           ;; Connect client
           (setf client-socket (usocket:socket-connect "127.0.0.1" port))
           (setf client-stream (usocket:socket-stream client-socket))
           
           ;; Wait a moment for connection to establish and handshaking to begin
           (sleep 0.1)
           
           ;; Server should ask for name
           (let ((line1 (read-line client-stream nil nil)))
             (is (equal line1 "What is your name?")))
           
           ;; Send player name
           (write-line "QuitTestPlayer" client-stream)
           (force-output client-stream)
           
           ;; Server should create character and send room description and greeting
           (sleep 0.1)
           ;; Read until we see the "Welcome to the MUD!" greeting
           (let ((greeting-found nil))
             (loop for line = (read-line client-stream nil nil)
                   while line
                   do (when (search "Welcome" line)
                        (setf greeting-found t)
                        (return)))
             (is (not (null greeting-found))))
           
           ;; Read next prompt "> "
           (let ((prompt (make-string 2)))
             (read-sequence prompt client-stream)
             (is (equal prompt "> ")))
           
           ;; Verify player exists in the world
           (let* ((world (mud::get-persistent-world))
                  (player (loop for p being the hash-values of (mud::world-players world)
                               when (equal (mud:object-name p) "QuitTestPlayer")
                                 return p)))
             (is (not (null player)))
             
             ;; Now send "quit"
             (write-line "quit" client-stream)
             (force-output client-stream)
             
             ;; Server should send "Goodbye!"
             (is (equal (read-line client-stream nil nil) "Goodbye!"))
             
             ;; Wait for session thread to cleanup
             (sleep 0.2)
             
             ;; Verify player is removed from the world
             (is (not (gethash (mud:object-id player) (mud::world-players world))))))
      ;; Cleanup
      (when client-stream (close client-stream))
      (when client-socket (usocket:socket-close client-socket))
      (mud:stop-mud-server))))

(test network-unexpected-disconnect-integration
  "Test a real client connecting, naming themselves, and abruptly disconnecting."
  (mud:stop-mud-server)
  (is (mud:start-mud-server :host "127.0.0.1" :port 0))
  (let* ((port (usocket:get-local-port mud::*server-socket*))
         (client-socket nil)
         (client-stream nil))
    (unwind-protect
         (progn
           ;; Connect client
           (setf client-socket (usocket:socket-connect "127.0.0.1" port))
           (setf client-stream (usocket:socket-stream client-socket))
           
           (sleep 0.1)
           
           ;; Server should ask for name
           (let ((line1 (read-line client-stream nil nil)))
             (is (equal line1 "What is your name?")))
           
           ;; Send player name
           (write-line "AbruptPlayer" client-stream)
           (force-output client-stream)
           
           (sleep 0.1)
           
           ;; Verify player is in world
           (let* ((world (mud::get-persistent-world))
                  (player (loop for p being the hash-values of (mud::world-players world)
                               when (equal (mud:object-name p) "AbruptPlayer")
                                 return p)))
             (is (not (null player)))
             
             ;; Now close client socket abruptly without quitting!
             (close client-stream)
             (usocket:socket-close client-socket)
             (setf client-stream nil
                   client-socket nil)
             
             ;; Wait for server loop to detect EOF / socket error and run cleanup
             (sleep 0.3)
             
             ;; Verify player is cleaned up from the world
             (is (not (gethash (mud:object-id player) (mud::world-players world))))))
      ;; Cleanup
      (when client-stream (close client-stream))
      (when client-socket (usocket:socket-close client-socket))
      (mud:stop-mud-server))))
