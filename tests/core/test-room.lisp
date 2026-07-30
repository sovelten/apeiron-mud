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
    (setf (apeiron.core:object-id alice) 1)
    (setf (apeiron.core:object-id bob) 2)
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
      
      (test connection-regular-block-blocks-all-characters
        "A regularly blocked connection blocks every character regardless of flags."
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
      
      (test connection-challenge-only-blocks-characters-without-flag
        "A challenge-gated connection blocks only characters who lack the flag."
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

(test cardinal-direction-format
  "Format cardinal directions with first-letter synonyms as (n)orth, (s)outh, etc."
  (let* ((world (new-world))
         (room1 (new-room :name "Room A"))
         (room2 (new-room :name "Room B"))
         (conn (connect-rooms! world room1 "north" room2 "south"
                 :synonyms-a '("n") :synonyms-b '("s"))))
    (is (string= "(n)orth" (format-exit-direction "north" conn room1))
        "Cardinal north with 'n' synonym should show as (n)orth")
    (is (string= "(s)outh" (format-exit-direction "south" conn room2))
        "Cardinal south with 's' synonym should show as (s)outh")))

(test non-cardinal-direction-format
  "Format non-cardinal directions with synonyms as Direction (syn)."
  (let* ((world (new-world))
         (room1 (new-room :name "Nexus"))
         (room2 (new-room :name "Forest"))
         (conn (connect-rooms! world room1 "Puzzling Forest" room2 "nexus"
                 :synonyms-a '("pf"))))
    (is (string= "Puzzling Forest (pf)" (format-exit-direction "Puzzling Forest" conn room1))
        "Non-cardinal direction should show as 'Direction (syn)'")))

(test multiple-synonyms-format
  "Format directions with multiple synonyms as Direction (syn1, syn2)."
  (let* ((world (new-world))
         (room1 (new-room :name "Hall"))
         (room2 (new-room :name "Garden"))
         (conn (connect-rooms! world room1 "doorway" room2 "gate"
                 :synonyms-a '("door" "dr") :synonyms-b '("g"))))
    (is (string= "doorway (door, dr)" (format-exit-direction "doorway" conn room1))
        "Multiple synonyms should show as 'Direction (syn1, syn2)'")))

(test no-synonyms-format
  "Format directions without synonyms as just the direction name."
  (let* ((world (new-world))
         (room1 (new-room :name "Room A"))
         (room2 (new-room :name "Room B"))
         (conn (connect-rooms! world room1 "north" room2 "south")))
    (is (string= "north" (format-exit-direction "north" conn room1))
        "Direction without synonyms should show as-is")))

(test synonyms-for-room-perspective
  "Test that synonyms-for-room returns synonyms from the correct perspective."
  (let* ((world (new-world))
         (room-a (new-room :name "Room A"))
         (room-b (new-room :name "Room B"))
         (conn (connect-rooms! world room-a "north" room-b "south"
                 :synonyms-a '("n") :synonyms-b '("s"))))
    (is (equal '("n") (synonyms-for-room conn room-a))
        "From room-a, synonyms should be 'n'")
    (is (equal '("s") (synonyms-for-room conn room-b))
        "From room-b, synonyms should be 's'")))

(test mixed-exits-description
  "Test that object-describe for a room with mixed exits shows proper formatting."
  (let* ((world (new-world))
         (hub (new-room :name "Central Hub"))
         (forest (new-room :name "Puzzling Forest"))
         (desert (new-room :name "Desert"))
         (cave (new-room :name "Cave")))
    (world-add-object! world hub)
    (world-add-object! world forest)
    (world-add-object! world desert)
    (world-add-object! world cave)
    ;; Custom named exit with synonym (direction names are downcased by connect-rooms!)
    (connect-rooms! world hub "Puzzling Forest" forest "nexus"
                    :synonyms-a '("pf"))
    ;; Cardinal exit with standard synonyms — hub is west-room, desert is east-room
    (connect-west-east! world hub desert)
    ;; Blocked exit
    (connect-rooms! world hub "tunnel" cave "entrance"
                    :blocked t)
    (let ((desc (object-describe hub)))
      (is (search "puzzling forest (pf)" desc)
          "Custom direction should show with synonym in parens (downcased)")
      (is (search "(e)ast" desc)
          "Cardinal east with 'e' synonym should show as (e)ast")
      (is (search "tunnel (blocked)" desc)
          "Blocked exit should show the direction name with (blocked) suffix"))))
