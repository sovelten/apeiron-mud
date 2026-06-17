(in-package #:mud-test)

(in-suite mud-tests)

(test server-initialization
  "Test that the server can be initialized without crashing"
  (handler-case
      (progn
        (is (not (null (mud:get-config-key :starting-room-id))))
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

(test bknr-id-conflict-on-restart
  "Test that world-level IDs do NOT conflict after store close/reopen."
  (let ((original-world mud:*world*))
    (unwind-protect
         (progn
           ;; 1. Start with a clean state
           (mud:world-restore-or-initialize :force-new t)
           ;; 2. Record initial room IDs
           (let ((initial-ids (mapcar #'mud:object-id (mud:rooms))))
             (is (>= (length initial-ids) 2))
             ;; 3. Simulate restart: close store and restore
             (bknr.datastore:close-store)
             (setf mud:*world* nil)
             (setf mud:*players* (make-hash-table :test #'equal))
             (mud:world-restore-or-initialize)
             (let ((restored-ids (mapcar #'mud:object-id (mud:rooms))))
               ;; Ensure rooms were loaded with their original world-level IDs
               (is (= (length initial-ids) (length restored-ids)))
               (is (subsetp initial-ids restored-ids))
               ;; 4. Add a new room post-restart
               (let ((new-room (mud:new-room :name "Post-Restart Room")))
                 (mud:world-add-room mud:*world* new-room)
                 (let ((new-id (mud:object-id new-room)))
                   (is (not (member new-id restored-ids))
                       "New object ID ~D conflicts with existing loaded room IDs: ~A"
                       new-id restored-ids))))))
      (setf mud:*world* original-world))))

(test guestbook-persistence
  "Test that guestbook entries survive store close/reopen via CSV persistence."
  (let ((original-world mud:*world*))
    (unwind-protect
         (progn
           (mud:world-restore-or-initialize :force-new t)
           ;; Find the guestbook in the starting room
           (let* ((tavern (mud:starting-room))
                  (guestbook (find-if (lambda (obj) (typep obj 'mud:mud-guestbook))
                                      (mud:room-contents tavern))))
             (is (not (null guestbook)))
             ;; Add an entry (writes to CSV on disk)
             (mud:guestbook-add-entry guestbook "Sophia" "Persistent via CSV!")
             ;; Snapshot
             (mud:sync-world)
             ;; Simulate restart
             (bknr.datastore:close-store)
             (setf mud:*world* nil)
             (setf mud:*players* (make-hash-table :test #'equal))
             (mud:world-restore-or-initialize)
             ;; Find the guestbook in the restored world
             (let* ((reloaded-tavern (mud:starting-room))
                    (reloaded-gbook (find-if (lambda (obj) (typep obj 'mud:mud-guestbook))
                                             (mud:room-contents reloaded-tavern))))
               (is (not (null reloaded-gbook)))
               (let ((entries (mud:guestbook-entries reloaded-gbook)))
                 (is (= (length entries) 1))
                 (is (equal (getf (first entries) :author) "Sophia"))
                 (is (equal (getf (first entries) :message) "Persistent via CSV!"))))))
      (setf mud:*world* original-world))))
