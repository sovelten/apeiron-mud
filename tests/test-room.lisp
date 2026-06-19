(in-package #:mud-test)

(in-suite mud-tests)

(test room-creation
  "Test that we can create rooms"
  (let ((room (mud:new-room :name "Test Room")))
    (unwind-protect
         (progn
           (is (typep room 'mud:mud-room))
           (is (equal (mud:object-name room) "Test Room")))
      (bknr.indices:destroy-object room))))

(test room-contents
  "Test room contents management"
  (let ((room (mud:new-room))
        (obj (mud:new-room)))
    (unwind-protect
         (progn
           (mud:room-add-object room obj)
           (is (> (length (mud:room-contents room)) 0)))
      (bknr.indices:destroy-object obj)
      (bknr.indices:destroy-object room))))

(test room-exits
  "Test room exit management"
  (let ((room1 (mud:new-room :name "Room 1"))
        (room2 (mud:new-room :name "Room 2")))
    (unwind-protect
         (progn
           (mud:room-add-exit room1 "north" room2)
           (is (eq (mud:room-get-exit room1 "north") room2)))
      (bknr.indices:destroy-object room2)
      (bknr.indices:destroy-object room1))))

(test room-add-exits
  "Test room exit management"
  (let ((room1 (mud:new-room :name "Room 1"))
        (room2 (mud:new-room :name "Room 2")))
    (unwind-protect
         (progn
           (mud:room-add-exits room1 "north" room2 "south")
           (is (eq (mud:room-get-exit room1 "north") room2))
           (is (eq (mud:room-get-exit room2 "south") room1)))
      (bknr.indices:destroy-object room2)
      (bknr.indices:destroy-object room1))))
