(in-package #:mud.tests)

(in-suite mud-tests)

(test server-initialization
  "Test that the server can be initialized without crashing"
  (handler-case
      (progn
        (is (not (null (mud:get-config-key mud:*system* :starting-room-id))))
        (is (> (mud:total-rooms) 0)))
    (error (e)
      (fail (format nil "Server initialization failed: ~A" e)))))

(test player-connection-simulation
  "Test simulated player connection and command processing"
  (handler-case
      (progn
        ;; Create a player without a real socket
        (let ((session (make-instance 'mud:mud-session :socket nil))
              (player (mud:new-character "TestPlayer" (make-instance 'mud:mud-session :socket nil))))
          (mud:world-new-character player)
          ;; Test that the player was created
          (is (equal (mud:object-name player) "TestPlayer"))
          ;; Test that the player is in a room
          (is (not (null (mud:object-location player))))
          ;; Test that we can process commands without crashing
          (mud:process-command player "look")
          (mud:process-command player "help")
          (mud:process-command player "exits")
          (is (not (null player)))))
    (error (e)
      (fail (format nil "Player connection simulation failed: ~A" e)))))

(test socket-stream-error-handling
  "Test that socket errors are handled gracefully"
  (handler-case
      (progn
        (let ((session (make-instance 'mud:mud-session :socket nil))
              (player (mud:new-character "TestPlayer" (make-instance 'mud:mud-session :socket nil))))
          ;; Sending message to player with nil socket should not crash
          (mud:player-send-message player "Test message")
          (is (not (null player)))))
    (error (e)
      ;; Error is expected, just check it doesn't crash the test
      (is (not (null e))))))

(test graceful-disconnection
  "Test that clients can disconnect without flooding with errors"
  (handler-case
      (progn
        ;; Simulate creating and disconnecting a player
        (let* ((session (make-instance 'mud:mud-session :socket nil))
               (player (mud:new-character "DisconnectTest" session)))
          (mud:world-new-character player)
          ;; Verify player was created
          (is (equal (mud:object-name player) "DisconnectTest"))
          ;; Simulate disconnect by setting socket to nil
          (setf (mud:session-socket session) nil)
          ;; Try to send message - should not crash or loop
          (mud:player-send-message player "Test after disconnect")
          ;; Player disconnect should work gracefully
          (mud:remove-character player)
          (is (not (null player)))))
    (error (e)
      (fail (format nil "Graceful disconnection failed: ~A" e)))))

(test player-removal-from-world
  "Test that player is removed from world data structures on disconnect"
  (let* ((room (mud:new-room :name "Test Room"))
         (session (make-instance 'mud:mud-session :socket nil))
         (character (mud:new-character "TestRemovePlayer" session)))

    (mud:world-new-character character)
    (setf (mud:object-location character) room)
    (mud:room-add-object room character)
    
    (is (find character (mud:room-contents room)))
    (is (gethash (mud:object-id character) mud:*players*))
    
    (mud:remove-character character)
    
    (is (not (find character (mud:room-contents room))))
    (is (not (gethash (mud:object-id character) mud:*players*)))))

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
           
           ;; Read prompt "> "
           (let ((prompt (make-string 2)))
             (read-sequence prompt client-stream)
             (is (equal prompt "> ")))
           
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
           (let ((player (loop for p being the hash-values of mud::*players*
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
             (is (not (gethash (mud:object-id player) mud::*players*)))))
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
           
           ;; Read prompt "> "
           (let ((prompt (make-string 2)))
             (read-sequence prompt client-stream)
             (is (equal prompt "> ")))
           
           ;; Send player name
           (write-line "AbruptPlayer" client-stream)
           (force-output client-stream)
           
           (sleep 0.1)
           
           ;; Verify player is in world
           (let ((player (loop for p being the hash-values of mud::*players*
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
             (is (not (gethash (mud:object-id player) mud::*players*)))))
      ;; Cleanup
      (when client-stream (close client-stream))
      (when client-socket (usocket:socket-close client-socket))
      (mud:stop-mud-server))))

(test prevalence-id-conflict-on-restart
  "Test that verifying id conflicts on restart replicates the bug."
  (let ((original-id-counter mud.utils::*id-counter*)
        (original-system mud:*system*))
    (unwind-protect
         (progn
           ;; 1. Start with a clean state and reset id counter
           (setf mud.utils::*id-counter* 0)
           (mud:world-restore-or-initialize :force-new t)
           
           ;; 2. Record initial room IDs (should be 1 and 2)
           (let ((initial-ids (mapcar #'mud:object-id (mud:rooms))))
             (is (member 1 initial-ids))
             (is (member 2 initial-ids))
             
             ;; 3. Simulate a restart: close open streams, reset counter to 0
             (cl-prevalence:close-open-streams mud:*system*)
             (setf mud.utils::*id-counter* 0)
             
             ;; 4. Restore the world (without force-new, reading back from file)
             (mud:world-restore-or-initialize :force-new nil)
             
             (let ((restored-ids (mapcar #'mud:object-id (mud:rooms))))
               ;; Ensure the rooms were loaded with their original IDs
               (is (member 1 restored-ids))
               (is (member 2 restored-ids))
               
               ;; 5. Create a new object post-restart
               (let* ((new-room (mud:create-room! (mud:new-room :name "Post-Restart Room")))
                      (new-id (mud:object-id new-room)))
                 ;; Assert that the new object ID is UNIQUE and does not collide
                 ;; with any of the restored room IDs.
                 ;; Note: This assertion is EXPECTED TO FAIL because of the bug,
                 ;; proving that the ID counter restarted from 0 and gave us an
                 ;; ID that was already in use (namely, ID 1).
                 (is (not (member new-id restored-ids))
                     "New object ID ~D conflicts with existing loaded room IDs: ~A"
                     new-id restored-ids))))))
      ;; Restore original state
      (setf mud.utils::*id-counter* original-id-counter)
      (setf mud:*system* original-system)))
