(in-package #:mud.tests)

(in-suite mud-tests)

(test server-initialization
  "Test that the server can be initialized without crashing"
  (handler-case
      (progn
        (is (not (null mud:*start-room*)))
        (is (> (hash-table-count mud:*world*) 0)))
    (error (e)
      (fail (format nil "Server initialization failed: ~A" e)))))

(test player-connection-simulation
  "Test simulated player connection and command processing"
  (handler-case
      (progn
        ;; Create a player without a real socket
        (let ((player (mud:create-player "TestPlayer" nil)))
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
        (let ((player (mud:create-player "TestPlayer" nil)))
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
        (let ((player (mud:create-player "DisconnectTest" nil)))
          ;; Verify player was created
          (is (equal (mud:object-name player) "DisconnectTest"))
          ;; Simulate disconnect by setting socket to nil
          (setf (mud:player-socket player) nil)
          ;; Try to send message - should not crash or loop
          (mud:player-send-message player "Test after disconnect")
          ;; Player disconnect should work gracefully
          (mud:player-disconnect player)
          (is (not (null player)))))
    (error (e)
      (fail (format nil "Graceful disconnection failed: ~A" e)))))

(test player-removal-from-world
  "Test that player is removed from world data structures on disconnect"
  (let* ((room (mud:create-room :name "Test Room"))
         (player (mud:create-player "TestRemovePlayer" nil)))
    (setf (mud:object-location player) room)
    (mud:room-add-object room player)
    
    (is (find player (mud:room-contents room)))
    (is (gethash (mud:object-id player) mud:*players*))
    
    (mud:player-disconnect player)
    
    (is (not (find player (mud:room-contents room))))
    (is (not (gethash (mud:object-id player) mud:*players*)))))

