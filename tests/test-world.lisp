(in-package #:mud-test)

(in-suite mud-tests)

(test get-config-key
  "Test reading config keys from a world"
  (let ((world (apeiron.core:new-world)))
    ;; Initially nil (default)
    (is (null (apeiron.core:get-config-key world :nothing)))
    ;; Set a value and read it back
    (setf (gethash :test-key (apeiron.core:world-config world)) "hello")
    (is (equal "hello" (apeiron.core:get-config-key world :test-key)))))

(test new-world
  "Test creating a fresh world with empty state"
  (let ((world (apeiron.core:new-world)))
    (is (typep world 'apeiron.core:mud-world))
    (is (= 0 (apeiron.core:world-id-counter world)))
    (is (eql 0 (hash-table-count (apeiron.core:world-players world))))
    (is (eql 0 (hash-table-count (apeiron.core:world-objects world))))
    (is (eql 0 (hash-table-count (apeiron.core:world-rooms world))))))

(test world-gen-id!
  "Test that world-gen-id! increments the counter and returns IDs"
  (let ((world (apeiron.core:new-world)))
    (is (= 1 (apeiron.core:world-gen-id! world)))
    (is (= 2 (apeiron.core:world-gen-id! world)))
    (is (= 3 (apeiron.core:world-gen-id! world)))
    ;; Counter persisted on world
    (is (= 3 (apeiron.core:world-id-counter world)))))

(test world-set-object-id!
  "Test assigning a world-level ID to an object and registering it"
  (let ((world (apeiron.core:new-world))
        (obj (apeiron.core:new-object :name "Widget")))
    (is (= -1 (apeiron.core:object-id obj)))
    (apeiron.core:world-set-object-id! world obj)
    (is (= 1 (apeiron.core:object-id obj)))
    (is (eq obj (apeiron.core:world-object-by-id world 1)))
    ;; Idempotent — second call does not re-assign
    (apeiron.core:world-set-object-id! world obj)
    (is (= 1 (apeiron.core:object-id obj)))))

(test world-set-object-id!-for-room
  "Test that world-set-object-id! on a room also registers in world rooms"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Lounge")))
    (apeiron.core:world-set-object-id! world room)
    (is (eq room (apeiron.core:world-room-by-id world (apeiron.core:object-id room))))))

(test world-set-starting-room!
  "Test setting the starting room in world config"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Entrance")))
    (apeiron.core:world-set-object-id! world room)
    (apeiron.core:world-set-starting-room! world room)
    (is (eq room (apeiron.core:starting-room world)))))

(test starting-room-nil
  "Test starting-room returns nil when not yet configured"
  (let ((world (apeiron.core:new-world)))
    (is (null (apeiron.core:starting-room world)))))

(test world-add-character!
  "Test adding a character places them in the world's starting room"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn"))
        (player (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:mud-session :socket nil))))
    (apeiron.core:world-set-object-id! world room)
    (apeiron.core:world-set-starting-room! world room)
    (apeiron.core:world-set-object-id! world player)
    (apeiron.core:world-add-character! world player)
    (is (eq room (apeiron.core:object-location player)))
    (is (eq player (apeiron.core:character-by-id world (apeiron.core:object-id player))))))

(test world-total-players
  "Test world-total-players counts active players"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn")))
    (apeiron.core:world-set-object-id! world room)
    (apeiron.core:world-set-starting-room! world room)
    (is (= 0 (apeiron.core:world-total-players world)))
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:mud-session :socket nil)))
          (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-set-object-id! world alice)
      (apeiron.core:world-add-character! world alice)
      (is (= 1 (apeiron.core:world-total-players world)))
      (apeiron.core:world-set-object-id! world bob)
      (apeiron.core:world-add-character! world bob)
      (is (= 2 (apeiron.core:world-total-players world))))))

(test world-remove-character!
  "Test removing a character from the world"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn")))
    (apeiron.core:world-set-object-id! world room)
    (apeiron.core:world-set-starting-room! world room)
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-set-object-id! world player)
      (apeiron.core:world-add-character! world player)
      (is (= 1 (apeiron.core:world-total-players world)))
      (apeiron.core:world-remove-character! world player)
      (is (= 0 (apeiron.core:world-total-players world)))
      (is (null (apeiron.core:character-by-id world (apeiron.core:object-id player)))))))

(test character-by-id-unknown
  "Test character-by-id returns nil for unknown ID"
  (let ((world (apeiron.core:new-world)))
    (is (null (apeiron.core:character-by-id world 999)))))

(test characters
  "Test characters returns the list of all active players"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn")))
    (apeiron.core:world-set-object-id! world room)
    (apeiron.core:world-set-starting-room! world room)
    (is (null (apeiron.core:characters world)))
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:mud-session :socket nil)))
          (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-set-object-id! world alice)
      (apeiron.core:world-add-character! world alice)
      (apeiron.core:world-set-object-id! world bob)
      (apeiron.core:world-add-character! world bob)
      (let ((chars (apeiron.core:characters world)))
        (is (= 2 (length chars)))
        (is (member alice chars))
        (is (member bob chars))))))

(test find-character-in-room
  "Test finding a character in a room by name (case-insensitive)"
  (let ((room (apeiron.core:new-room :name "Tavern"))
        (alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:mud-session :socket nil)))
        (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:mud-session :socket nil))))
    (setf (apeiron.core:object-location alice) room)
    (setf (apeiron.core:object-location bob) room)
    (apeiron.core:room-add-object room alice)
    (apeiron.core:room-add-object room bob)
    (is (eq alice (apeiron.core:find-character-in-room room "Alice")))
    (is (eq bob (apeiron.core:find-character-in-room room "Bob")))
    ;; Case-insensitive match
    (is (eq alice (apeiron.core:find-character-in-room room "alice")))
    ;; Non-existent name returns nil
    (is (null (apeiron.core:find-character-in-room room "Charlie")))))

(test world-broadcast
  "Test broadcasting a message to all players"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn"))
        (msgs-a (make-array 0 :adjustable t :fill-pointer t))
        (msgs-b (make-array 0 :adjustable t :fill-pointer t)))
    (apeiron.core:world-set-object-id! world room)
    (apeiron.core:world-set-starting-room! world room)
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:mud-session :socket nil)))
          (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:mud-session :socket nil))))
      ;; Capture messages addressed to each player's session via :after method
      (defmethod apeiron.core:mud-write :after ((session (eql (apeiron.core:character-session alice))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-a))
      (defmethod apeiron.core:mud-write :after ((session (eql (apeiron.core:character-session bob))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-b))
      (apeiron.core:world-set-object-id! world alice)
      (apeiron.core:world-add-character! world alice)
      (apeiron.core:world-set-object-id! world bob)
      (apeiron.core:world-add-character! world bob)
      (apeiron.core:world-broadcast world "Hello everyone!")
      (is (= 1 (length msgs-a)))
      (is (equal "Hello everyone!" (aref msgs-a 0)))
      (is (= 1 (length msgs-b)))
      (is (equal "Hello everyone!" (aref msgs-b 0))))))

(test world-broadcast-exclude
  "Test broadcasting excludes the specified player"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn"))
        (msgs-a (make-array 0 :adjustable t :fill-pointer t))
        (msgs-b (make-array 0 :adjustable t :fill-pointer t)))
    (apeiron.core:world-set-object-id! world room)
    (apeiron.core:world-set-starting-room! world room)
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:mud-session :socket nil)))
          (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:mud-session :socket nil))))
      (defmethod apeiron.core:mud-write :after ((session (eql (apeiron.core:character-session alice))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-a))
      (defmethod apeiron.core:mud-write :after ((session (eql (apeiron.core:character-session bob))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-b))
      (apeiron.core:world-set-object-id! world alice)
      (apeiron.core:world-add-character! world alice)
      (apeiron.core:world-set-object-id! world bob)
      (apeiron.core:world-add-character! world bob)
      (apeiron.core:world-broadcast world "Secret" bob)
      (is (= 1 (length msgs-a)))
      (is (equal "Secret" (aref msgs-a 0)))
      (is (= 0 (length msgs-b))
          "Bob (the exclude-player) should not receive the message"))))

(test world-object-by-id
  "Test looking up an object by its world-level ID"
  (let ((world (apeiron.core:new-world))
        (obj (apeiron.core:new-object :name "Sword")))
    (apeiron.core:world-set-object-id! world obj)
    (is (eq obj (apeiron.core:world-object-by-id world (apeiron.core:object-id obj))))
    (is (null (apeiron.core:world-object-by-id world 999)))))

(test world-object-with-name
  "Test finding objects by name (case-insensitive)"
  (let ((world (apeiron.core:new-world)))
    (let ((sword  (apeiron.core:new-object :name "Sword"))
          (shield (apeiron.core:new-object :name "Shield"))
          (sword2 (apeiron.core:new-object :name "sword")))
      (apeiron.core:world-set-object-id! world sword)
      (apeiron.core:world-set-object-id! world shield)
      (apeiron.core:world-set-object-id! world sword2)
      (let ((results (apeiron.core:world-object-with-name world "Sword")))
        (is (= 2 (length results)))
        (is (member sword results))
        (is (member sword2 results)))
      (is (null (apeiron.core:world-object-with-name world "Axe"))))))

(test world-all-objects
  "Test returning all objects registered in the world"
  (let ((world (apeiron.core:new-world)))
    (is (null (apeiron.core:world-all-objects world)))
    (let ((a (apeiron.core:new-object :name "A"))
          (b (apeiron.core:new-object :name "B")))
      (apeiron.core:world-set-object-id! world a)
      (is (= 1 (length (apeiron.core:world-all-objects world))))
      (apeiron.core:world-set-object-id! world b)
      (let ((all (apeiron.core:world-all-objects world)))
        (is (= 2 (length all)))
        (is (member a all))
        (is (member b all))))))

(test world-room-by-id
  "Test looking up a room by its world-level ID"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Kitchen")))
    (apeiron.core:world-set-object-id! world room)
    (is (eq room (apeiron.core:world-room-by-id world (apeiron.core:object-id room))))
    (is (null (apeiron.core:world-room-by-id world 999)))))

(test world-total-rooms
  "Test counting rooms in the world"
  (let ((world (apeiron.core:new-world)))
    (is (= 0 (apeiron.core:world-total-rooms world)))
    (let ((r1 (apeiron.core:new-room :name "R1"))
          (r2 (apeiron.core:new-room :name "R2")))
      (apeiron.core:world-set-object-id! world r1)
      (is (= 1 (apeiron.core:world-total-rooms world)))
      (apeiron.core:world-set-object-id! world r2)
      (is (= 2 (apeiron.core:world-total-rooms world))))))
