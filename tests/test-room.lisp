(in-package #:mud-test)

(in-suite mud-tests)

(test room-creation
  "Test that we can create rooms"
  (let ((room (apeiron.core:new-room :name "Test Room")))
    (is (typep room 'apeiron.core:mud-room))
    (is (equal (apeiron.core:object-name room) "Test Room"))))

(test room-contents
  "Test room contents management"
  (let ((room (apeiron.core:new-room))
        (obj (apeiron.core:new-room)))
    (apeiron.core:room-add-object room obj)
    (is (> (length (apeiron.core:room-contents room)) 0))))

(test room-exits
  "Test room exit management"
  (let ((room1 (apeiron.core:new-room :name "Room 1"))
        (room2 (apeiron.core:new-room :name "Room 2")))
    (apeiron.core:room-add-exit room1 "north" room2)
    (is (eq (apeiron.core:room-get-exit room1 "north") room2))))

(test room-add-exits
  "Test room exit management"
  (let ((room1 (apeiron.core:new-room :name "Room 1"))
        (room2 (apeiron.core:new-room :name "Room 2")))
    (apeiron.core:room-add-exits room1 "north" room2 "south")
    (is (eq (apeiron.core:room-get-exit room1 "north") room2))
    (is (eq (apeiron.core:room-get-exit room2 "south") room1))))
