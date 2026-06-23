(in-package #:mud-test)

(in-suite mud-tests)

(test get-config-key
  "Test reading config keys from a world"
  (let ((world (mud:new-world)))
    ;; Initially nil (default)
    (is (null (mud::get-config-key world :nothing)))
    ;; Set a value and read it back
    (setf (gethash :test-key (mud::world-config world)) "hello")
    (is (equal "hello" (mud::get-config-key world :test-key)))))

(test new-world
  "Test creating a fresh world with empty state"
  (let ((world (mud:new-world)))
    (is (typep world 'mud::mud-world))
    (is (= 0 (mud::world-id-counter world)))
    (is (eql 0 (hash-table-count (mud::world-players world))))
    (is (eql 0 (hash-table-count (mud::world-objects world))))
    (is (eql 0 (hash-table-count (mud::world-rooms world))))))

(test world-gen-id!
  "Test that world-gen-id! increments the counter and returns IDs"
  (let ((world (mud:new-world)))
    (is (= 1 (mud::world-gen-id! world)))
    (is (= 2 (mud::world-gen-id! world)))
    (is (= 3 (mud::world-gen-id! world)))
    ;; Counter persisted on world
    (is (= 3 (mud::world-id-counter world)))))

(test world-set-object-id!
  "Test assigning a world-level ID to an object and registering it"
  (let ((world (mud:new-world))
        (obj (mud:new-object :name "Widget")))
    (is (= -1 (mud:object-id obj)))
    (mud:world-set-object-id! world obj)
    (is (= 1 (mud:object-id obj)))
    (is (eq obj (mud:world-object-by-id world 1)))
    ;; Idempotent — second call does not re-assign
    (mud:world-set-object-id! world obj)
    (is (= 1 (mud:object-id obj)))))

(test world-set-object-id!-for-room
  "Test that world-set-object-id! on a room also registers in world rooms"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Lounge")))
    (mud:world-set-object-id! world room)
    (is (eq room (mud:world-room-by-id world (mud:object-id room))))))

(test world-set-starting-room!
  "Test setting the starting room in world config"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Entrance")))
    (mud:world-set-object-id! world room)
    (mud::world-set-starting-room! world room)
    (is (eq room (mud:starting-room world)))))

(test starting-room-nil
  "Test starting-room returns nil when not yet configured"
  (let ((world (mud:new-world)))
    (is (null (mud:starting-room world)))))

(test world-add-character!
  "Test adding a character places them in the world's starting room"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Spawn"))
        (player (mud:new-character "Alice" (make-instance 'mud:mud-session :socket nil))))
    (mud:world-set-object-id! world room)
    (mud::world-set-starting-room! world room)
    (mud:world-set-object-id! world player)
    (mud:world-add-character! world player)
    (is (eq room (mud:object-location player)))
    (is (eq player (mud:character-by-id world (mud:object-id player))))))

(test world-total-players
  "Test world-total-players counts active players"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Spawn")))
    (mud:world-set-object-id! world room)
    (mud::world-set-starting-room! world room)
    (is (= 0 (mud::world-total-players world)))
    (let ((alice (mud:new-character "Alice" (make-instance 'mud:mud-session :socket nil)))
          (bob   (mud:new-character "Bob"   (make-instance 'mud:mud-session :socket nil))))
      (mud:world-set-object-id! world alice)
      (mud:world-add-character! world alice)
      (is (= 1 (mud::world-total-players world)))
      (mud:world-set-object-id! world bob)
      (mud:world-add-character! world bob)
      (is (= 2 (mud::world-total-players world))))))

(test world-remove-character!
  "Test removing a character from the world"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Spawn")))
    (mud:world-set-object-id! world room)
    (mud::world-set-starting-room! world room)
    (let ((player (mud:new-character "TestPlayer" (make-instance 'mud:mud-session :socket nil))))
      (mud:world-set-object-id! world player)
      (mud:world-add-character! world player)
      (is (= 1 (mud::world-total-players world)))
      (mud:world-remove-character! world player)
      (is (= 0 (mud::world-total-players world)))
      (is (null (mud:character-by-id world (mud:object-id player)))))))

(test character-by-id-unknown
  "Test character-by-id returns nil for unknown ID"
  (let ((world (mud:new-world)))
    (is (null (mud:character-by-id world 999)))))

(test characters
  "Test characters returns the list of all active players"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Spawn")))
    (mud:world-set-object-id! world room)
    (mud::world-set-starting-room! world room)
    (is (null (mud::characters world)))
    (let ((alice (mud:new-character "Alice" (make-instance 'mud:mud-session :socket nil)))
          (bob   (mud:new-character "Bob"   (make-instance 'mud:mud-session :socket nil))))
      (mud:world-set-object-id! world alice)
      (mud:world-add-character! world alice)
      (mud:world-set-object-id! world bob)
      (mud:world-add-character! world bob)
      (let ((chars (mud::characters world)))
        (is (= 2 (length chars)))
        (is (member alice chars))
        (is (member bob chars))))))

(test find-character-in-room
  "Test finding a character in a room by name (case-insensitive)"
  (let ((room (mud:new-room :name "Tavern"))
        (alice (mud:new-character "Alice" (make-instance 'mud:mud-session :socket nil)))
        (bob   (mud:new-character "Bob"   (make-instance 'mud:mud-session :socket nil))))
    (setf (mud:object-location alice) room)
    (setf (mud:object-location bob) room)
    (mud:room-add-object room alice)
    (mud:room-add-object room bob)
    (is (eq alice (mud::find-character-in-room room "Alice")))
    (is (eq bob (mud::find-character-in-room room "Bob")))
    ;; Case-insensitive match
    (is (eq alice (mud::find-character-in-room room "alice")))
    ;; Non-existent name returns nil
    (is (null (mud::find-character-in-room room "Charlie")))))

(test world-broadcast
  "Test broadcasting a message to all players"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Spawn"))
        (msgs-a (make-array 0 :adjustable t :fill-pointer t))
        (msgs-b (make-array 0 :adjustable t :fill-pointer t)))
    (mud:world-set-object-id! world room)
    (mud::world-set-starting-room! world room)
    (let ((alice (mud:new-character "Alice" (make-instance 'mud:mud-session :socket nil)))
          (bob   (mud:new-character "Bob"   (make-instance 'mud:mud-session :socket nil))))
      ;; Capture messages addressed to each player's session via :after method
      (defmethod mud::mud-write :after ((session (eql (mud::character-session alice))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-a))
      (defmethod mud::mud-write :after ((session (eql (mud::character-session bob))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-b))
      (mud:world-set-object-id! world alice)
      (mud:world-add-character! world alice)
      (mud:world-set-object-id! world bob)
      (mud:world-add-character! world bob)
      (mud::world-broadcast world "Hello everyone!")
      (is (= 1 (length msgs-a)))
      (is (equal "Hello everyone!" (aref msgs-a 0)))
      (is (= 1 (length msgs-b)))
      (is (equal "Hello everyone!" (aref msgs-b 0))))))

(test world-broadcast-exclude
  "Test broadcasting excludes the specified player"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Spawn"))
        (msgs-a (make-array 0 :adjustable t :fill-pointer t))
        (msgs-b (make-array 0 :adjustable t :fill-pointer t)))
    (mud:world-set-object-id! world room)
    (mud::world-set-starting-room! world room)
    (let ((alice (mud:new-character "Alice" (make-instance 'mud:mud-session :socket nil)))
          (bob   (mud:new-character "Bob"   (make-instance 'mud:mud-session :socket nil))))
      (defmethod mud::mud-write :after ((session (eql (mud::character-session alice))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-a))
      (defmethod mud::mud-write :after ((session (eql (mud::character-session bob))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-b))
      (mud:world-set-object-id! world alice)
      (mud:world-add-character! world alice)
      (mud:world-set-object-id! world bob)
      (mud:world-add-character! world bob)
      (mud::world-broadcast world "Secret" bob)
      (is (= 1 (length msgs-a)))
      (is (equal "Secret" (aref msgs-a 0)))
      (is (= 0 (length msgs-b))
          "Bob (the exclude-player) should not receive the message"))))

(test world-object-by-id
  "Test looking up an object by its world-level ID"
  (let ((world (mud:new-world))
        (obj (mud:new-object :name "Sword")))
    (mud:world-set-object-id! world obj)
    (is (eq obj (mud:world-object-by-id world (mud:object-id obj))))
    (is (null (mud:world-object-by-id world 999)))))

(test world-object-with-name
  "Test finding objects by name (case-insensitive)"
  (let ((world (mud:new-world)))
    (let ((sword  (mud:new-object :name "Sword"))
          (shield (mud:new-object :name "Shield"))
          (sword2 (mud:new-object :name "sword")))
      (mud:world-set-object-id! world sword)
      (mud:world-set-object-id! world shield)
      (mud:world-set-object-id! world sword2)
      (let ((results (mud:world-object-with-name world "Sword")))
        (is (= 2 (length results)))
        (is (member sword results))
        (is (member sword2 results)))
      (is (null (mud:world-object-with-name world "Axe"))))))

(test world-all-objects
  "Test returning all objects registered in the world"
  (let ((world (mud:new-world)))
    (is (null (mud:world-all-objects world)))
    (let ((a (mud:new-object :name "A"))
          (b (mud:new-object :name "B")))
      (mud:world-set-object-id! world a)
      (is (= 1 (length (mud:world-all-objects world))))
      (mud:world-set-object-id! world b)
      (let ((all (mud:world-all-objects world)))
        (is (= 2 (length all)))
        (is (member a all))
        (is (member b all))))))

(test world-room-by-id
  "Test looking up a room by its world-level ID"
  (let ((world (mud:new-world))
        (room (mud:new-room :name "Kitchen")))
    (mud:world-set-object-id! world room)
    (is (eq room (mud:world-room-by-id world (mud:object-id room))))
    (is (null (mud:world-room-by-id world 999)))))

(test world-total-rooms
  "Test counting rooms in the world"
  (let ((world (mud:new-world)))
    (is (= 0 (mud:world-total-rooms world)))
    (let ((r1 (mud:new-room :name "R1"))
          (r2 (mud:new-room :name "R2")))
      (mud:world-set-object-id! world r1)
      (is (= 1 (mud:world-total-rooms world)))
      (mud:world-set-object-id! world r2)
      (is (= 2 (mud:world-total-rooms world))))))
