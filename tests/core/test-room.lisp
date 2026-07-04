(in-package #:apeiron-test)

(in-suite core-suite)

(test room-creation
  "Test that we can create rooms"
  (let ((room (apeiron.core:new-room :name "Test Room")))
    (is (typep room 'apeiron.core:mud-room))
    (is (equal (apeiron.core:object-name room) "Test Room"))))

(test room-contents
  "Test room contents management"
  (let ((room (apeiron.core:new-room))
        (obj (apeiron.core:new-room)))
    (apeiron.core:container-add-object room obj)
    (is (= 1 (hash-table-count (apeiron.core:container-contents room))))))

(test find-character-in-room
  "Test finding a character in a room by name (case-insensitive)"
  (let ((room (apeiron.core:new-room :name "Tavern"))
        (alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
        (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
    (setf (apeiron.core:object-location alice) room)
    (setf (apeiron.core:object-location bob) room)
    (apeiron.core:container-add-object room alice)
    (apeiron.core:container-add-object room bob)
    (is (eq alice (apeiron.core:find-character-in-room room "Alice")))
    (is (eq bob (apeiron.core:find-character-in-room room "Bob")))
    ;; Case-insensitive match
    (is (eq alice (apeiron.core:find-character-in-room room "alice")))
    ;; Non-existent name returns nil
    (is (null (apeiron.core:find-character-in-room room "Charlie")))))

(test connection-bidirectional
  "Test that connect-rooms creates a bidirectional connection"
  (let ((world (new-world))
        (room1 (new-room :name "Forest"))
        (room2 (new-room :name "Cave")))
    (let ((conn (connect-rooms! world room1 "north" room2 "south"
                  :name "forest-cave passage")))
      (is (typep conn 'mud-connection))
      (is (eq (room-exit-target room1 "north") room2))
      (is (eq (room-exit-target room2 "south") room1))
      (is (find conn (room-connections room1)))
      (is (find conn (room-connections room2)))
      (is (eq (connection-other-room conn room1) room2))
      (is (string= (connection-direction-to conn room1) "north"))
      (is (string= (connection-direction-to conn room2) "south"))
      (is (eq (connection-find room1 "north") conn))
      (is (null (connection-find room1 "east")))
      (is (null (connection-blocked-p conn)))
      ;; world-object-by-id should find it
      (is (eq conn (world-object-by-id world (object-id conn)))))))

(test connection-blocked
  "Test that blocked connections prevent movement"
  (let ((world (new-world))
        (room1 (new-room :name "Forest"))
        (room2 (new-room :name "Cave")))
    (let ((conn (connect-rooms! world room1 "north" room2 "south"
                  :name "locked gate"
                  :blocked t)))
      (is-true (connection-blocked-p conn))
      (is (eq (connection-find room1 "north") conn))
      (is (stringp (connection-exit-blocked-message room1 "north")))
      (is (search "blocked" (connection-exit-blocked-message room1 "north")))
      ;; Toggle unblocked
      (setf (connection-blocked-p conn) nil)
      (is-false (connection-blocked-p conn))
            (is (null (connection-exit-blocked-message room1 "north"))))))
      
      (test connection-regular-block-blocks-all-players
        "A regularly blocked connection blocks every player regardless of flags."
        (let* ((world (new-world))
               (room1 (new-room :name "Hall"))
               (room2 (new-room :name "Vault"))
               (alice (new-character "Alice" (make-instance 'stream-session
                                             :stream (make-string-output-stream))))
               (bob   (new-character "Bob"   (make-instance 'stream-session
                                             :stream (make-string-output-stream)))))
          (object-move alice room1)
          (object-move bob room1)
          (let ((conn (connect-rooms! world room1 "north" room2 "south"
                        :name "iron gate"
                        :blocked t)))
            (is (stringp (room-exit-blocked-p room1 alice "north")))
            (is (stringp (room-exit-blocked-p room1 bob "north")))
            (setf (connection-blocked-p conn) nil)
            (is (null (room-exit-blocked-p room1 alice "north")))
            (is (null (room-exit-blocked-p room1 bob "north"))))))
      
      (test connection-challenge-only-blocks-players-without-flag
        "A challenge-gated connection blocks only players who lack the flag."
        (let* ((world (new-world))
               (room1 (new-room :name "Library"))
               (room2 (new-room :name "Archive"))
               (alice (new-character "Alice" (make-instance 'stream-session
                                             :stream (make-string-output-stream))))
               (bob   (new-character "Bob"   (make-instance 'stream-session
                                             :stream (make-string-output-stream)))))
          (object-move alice room1)
          (object-move bob room1)
          (let ((conn (connect-rooms! world room1 "north" room2 "south")))
                  (object-set-property conn "challenge-flag" "passed-test")
                  (object-set-property conn "challenge-question" "What is 2+2?")
            (is (stringp (room-exit-blocked-p room1 alice "north")))
            (is (stringp (room-exit-blocked-p room1 bob "north")))
            (object-set-property alice "passed-test" t)
            (is (null (room-exit-blocked-p room1 alice "north")))
            (is (stringp (room-exit-blocked-p room1 bob "north"))))))
