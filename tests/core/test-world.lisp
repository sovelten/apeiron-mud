(in-package #:apeiron-test)

(in-suite core-suite)

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
    (is (eql 0 (hash-table-count (apeiron.core:world-characters world))))
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

(test world-add-object!
  "Test assigning a world-level ID to an object and registering it"
  (let ((world (apeiron.core:new-world))
        (obj (apeiron.core:new-object :name "Widget")))
    (is (= -1 (apeiron.core:object-id obj)))
    (apeiron.core:world-add-object! world obj)
    (is (= 1 (apeiron.core:object-id obj)))
    (is (eq obj (apeiron.core:world-object-by-id world 1)))
    ;; Idempotent — second call does not re-assign
    (apeiron.core:world-add-object! world obj)
    (is (= 1 (apeiron.core:object-id obj)))))

(test world-add-object!-for-room
  "Test that world-add-object! on a room also registers in world rooms"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Lounge")))
    (apeiron.core:world-add-object! world room)
    (is (eq room (apeiron.core:world-room-by-id world (apeiron.core:object-id room))))))

(test create-object!-without-room
  "create-object! without ROOM registers the object in the world but
does not place it anywhere (location stays NIL)."
  (let ((world (apeiron.core:new-world))
        (obj (apeiron.core:new-object :name "Vase")))
    (let ((created (apeiron.core:create-object! world obj)))
      (is (eq created obj))
      (is (null (apeiron.core:object-location obj)))
      (is (eq obj (apeiron.core:world-object-by-id world (apeiron.core:object-id obj)))))))

(test create-object!-with-room
  "create-object! with the optional ROOM argument registers the object
in the world AND places it in the room: its location is set to the room
and it is added to the room's contents."
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Lounge"))
        (obj (apeiron.core:new-object :name "Vase")))
    (apeiron.core:world-add-object! world room)
    (let ((created (apeiron.core:create-object! world obj room)))
      (is (eq created obj))
      (is (eq room (apeiron.core:object-location obj)))
      (is (member obj (apeiron.core:container-all-objects room) :test #'eq))
      ;; Also registered in the world's object index
      (is (eq obj (apeiron.core:world-object-by-id world (apeiron.core:object-id obj)))))))

(test world-set-starting-room!
  "Test setting the starting room in world config"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Entrance")))
    (apeiron.core:world-add-object! world room)
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
        (character (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-set-starting-room! world room)
    (apeiron.core:world-add-object! world character)
    (apeiron.core:place-character! world character)
    (is (eq room (apeiron.core:object-location character)))
    (is (eq character (apeiron.core:character-by-id world (apeiron.core:object-id character))))))

(test world-total-characters
  "Test world-total-characters counts active characters"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn")))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-set-starting-room! world room)
    (is (= 0 (apeiron.core:world-total-characters world)))
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
          (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-object! world alice)
      (apeiron.core:create-object! world alice)
      (is (= 1 (apeiron.core:world-total-characters world)))
      (apeiron.core:world-add-object! world bob)
      (apeiron.core:create-object! world bob)
      (is (= 2 (apeiron.core:world-total-characters world))))))

(test world-remove-character!
  "Test removing a character from the world"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn")))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-set-starting-room! world room)
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-object! world character)
      (apeiron.core:create-object! world character)
      (is (= 1 (apeiron.core:world-total-characters world)))
      (apeiron.core:world-remove-character! world character)
      (is (= 0 (apeiron.core:world-total-characters world)))
      (is (null (apeiron.core:character-by-id world (apeiron.core:object-id character)))))))

(test character-by-id-unknown
  "Test character-by-id returns nil for unknown ID"
  (let ((world (apeiron.core:new-world)))
    (is (null (apeiron.core:character-by-id world 999)))))

(test characters
  "Test characters returns the list of all active characters"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn")))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-set-starting-room! world room)
    (is (null (apeiron.core:characters world)))
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
          (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-object! world alice)
      (apeiron.core:create-object! world alice)
      (apeiron.core:world-add-object! world bob)
      (apeiron.core:create-object! world bob)
      (let ((chars (apeiron.core:characters world)))
        (is (= 2 (length chars)))
        (is (member alice chars))
        (is (member bob chars))))))

(test world-broadcast
  "Test broadcasting a message to all characters"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn"))
        (msgs-a (make-array 0 :adjustable t :fill-pointer t))
        (msgs-b (make-array 0 :adjustable t :fill-pointer t)))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-set-starting-room! world room)
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
          (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      ;; Capture messages addressed to each character's session via :after method
      (defmethod apeiron.core:mud-write :after ((session (eql (apeiron.core:character-session alice))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-a))
      (defmethod apeiron.core:mud-write :after ((session (eql (apeiron.core:character-session bob))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-b))
      (apeiron.core:world-add-object! world alice)
      (apeiron.core:create-object! world alice)
      (apeiron.core:world-add-object! world bob)
      (apeiron.core:create-object! world bob)
      (apeiron.core:world-broadcast world "Hello everyone!")
      (is (= 1 (length msgs-a)))
      (is (equal "Hello everyone!" (aref msgs-a 0)))
      (is (= 1 (length msgs-b)))
      (is (equal "Hello everyone!" (aref msgs-b 0))))))

(test world-broadcast-exclude
  "Test broadcasting excludes the specified character"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Spawn"))
        (msgs-a (make-array 0 :adjustable t :fill-pointer t))
        (msgs-b (make-array 0 :adjustable t :fill-pointer t)))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-set-starting-room! world room)
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
          (bob   (apeiron.core:new-character "Bob"   (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (defmethod apeiron.core:mud-write :after ((session (eql (apeiron.core:character-session alice))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-a))
      (defmethod apeiron.core:mud-write :after ((session (eql (apeiron.core:character-session bob))) msg &key newline)
        (declare (ignore newline))
        (vector-push-extend msg msgs-b))
      (apeiron.core:world-add-object! world alice)
      (apeiron.core:create-object! world alice)
      (apeiron.core:world-add-object! world bob)
      (apeiron.core:create-object! world bob)
      (apeiron.core:world-broadcast world "Secret" bob)
      (is (= 1 (length msgs-a)))
      (is (equal "Secret" (aref msgs-a 0)))
      (is (= 0 (length msgs-b))
          "Bob (the exclude-character) should not receive the message"))))

(test world-object-by-id
  "Test looking up an object by its world-level ID"
  (let ((world (apeiron.core:new-world))
        (obj (apeiron.core:new-object :name "Sword")))
    (apeiron.core:world-add-object! world obj)
    (is (eq obj (apeiron.core:world-object-by-id world (apeiron.core:object-id obj))))
    (is (null (apeiron.core:world-object-by-id world 999)))))

(test world-object-with-name
  "Test finding an object by name (case-insensitive)"
  (let ((world (apeiron.core:new-world)))
    (let ((sword  (apeiron.core:new-object :name "Sword"))
          (shield (apeiron.core:new-object :name "Shield")))
      (apeiron.core:world-add-object! world sword)
      (apeiron.core:world-add-object! world shield)
      (is (eq sword (apeiron.core:world-object-with-name world "Sword")))
      (is (eq sword (apeiron.core:world-object-with-name world "sword")))
      (is (eq shield (apeiron.core:world-object-with-name world "Shield")))
      (is (null (apeiron.core:world-object-with-name world "Axe"))))))

(test world-all-objects
  "Test returning all objects registered in the world"
  (let ((world (apeiron.core:new-world)))
    (is (null (apeiron.core:world-all-objects world)))
    (let ((a (apeiron.core:new-object :name "A"))
          (b (apeiron.core:new-object :name "B")))
      (apeiron.core:world-add-object! world a)
      (is (= 1 (length (apeiron.core:world-all-objects world))))
      (apeiron.core:world-add-object! world b)
      (let ((all (apeiron.core:world-all-objects world)))
        (is (= 2 (length all)))
        (is (member a all))
        (is (member b all))))))

(test world-room-by-id
  "Test looking up a room by its world-level ID"
  (let ((world (apeiron.core:new-world))
        (room (apeiron.core:new-room :name "Kitchen")))
    (apeiron.core:world-add-object! world room)
    (is (eq room (apeiron.core:world-room-by-id world (apeiron.core:object-id room))))
    (is (null (apeiron.core:world-room-by-id world 999)))))

(test world-total-rooms
  "Test counting rooms in the world"
  (let ((world (apeiron.core:new-world)))
    (is (= 0 (apeiron.core:world-total-rooms world)))
    (let ((r1 (apeiron.core:new-room :name "R1"))
          (r2 (apeiron.core:new-room :name "R2")))
      (apeiron.core:world-add-object! world r1)
      (is (= 1 (apeiron.core:world-total-rooms world)))
      (apeiron.core:world-add-object! world r2)
      (is (= 2 (apeiron.core:world-total-rooms world))))))

(test world-objects-matching
  "Test finding all objects matching by name, words, or aliases"
  (let ((world (apeiron.core:new-world)))
    (let ((guard   (apeiron.core:new-object :name "Guard"))
          (old-man (apeiron.core:new-object :name "Old Man"))
          (sword   (apeiron.core:new-object :name "Rusty Sword")))
      (setf (apeiron.core:object-aliases old-man) '("elder"))
      (apeiron.core:world-add-object! world guard)
      (apeiron.core:world-add-object! world old-man)
      (apeiron.core:world-add-object! world sword)
      ;; Exact name match
      (is (= 1 (length (apeiron.core:world-objects-matching world "Guard"))))
      (is (eq guard (first (apeiron.core:world-objects-matching world "Guard"))))
      ;; Case-insensitive exact match
      (is (= 1 (length (apeiron.core:world-objects-matching world "guard"))))
      ;; Whole-word match (Sword matches "Rusty Sword" via the word "Sword")
      (is (= 1 (length (apeiron.core:world-objects-matching world "Sword"))))
      (is (eq sword (first (apeiron.core:world-objects-matching world "Sword"))))
      ;; Whole-word match (Rusty matches "Rusty Sword" via the word "Rusty")
      (is (= 1 (length (apeiron.core:world-objects-matching world "Rusty"))))
      ;; Alias match
      (is (= 1 (length (apeiron.core:world-objects-matching world "elder"))))
      (is (eq old-man (first (apeiron.core:world-objects-matching world "elder"))))
      ;; No match returns empty list
      (is (null (apeiron.core:world-objects-matching world "Axe")))
      (is (null (apeiron.core:world-objects-matching world ""))))))
