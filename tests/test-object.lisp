(in-package #:mud.tests)

(in-suite mud-tests)

(test object-creation
  "Test that we can create basic objects"
  (let ((obj (mud:new-object :name "Test Object")))
    (is (stringp (mud:object-describe obj)))
    (is (equal (mud:object-name obj) "Test Object"))))

(test object-properties
  "Test object property storage"
  (let ((obj (mud:new-object)))
    (mud:object-set-property obj "test-prop" "test-value")
    (is (equal (mud:object-get-property obj "test-prop") "test-value"))))

(test room-creation
  "Test that we can create rooms"
  (let ((room (mud:new-room :name "Test Room")))
    (is (typep room 'mud:mud-room))
    (is (equal (mud:object-name room) "Test Room"))))

(test room-contents
  "Test room contents management"
  (let ((room (mud:new-room))
        (obj (mud:new-room)))
    (mud:room-add-object room obj)
    (is (> (length (mud:room-contents room)) 0))))

(test room-exits
  "Test room exit management"
  (let ((room1 (mud:new-room :name "Room 1"))
        (room2 (mud:new-room :name "Room 2")))
    (mud:room-add-exit room1 "north" room2)
    (is (eq (mud:room-get-exit room1 "north") room2))))

(test room-add-exits
  "Test room exit management"
  (let ((room1 (mud:new-room :name "Room 1"))
        (room2 (mud:new-room :name "Room 2")))
    (mud:room-add-exits room1 "north" room2 "south")
    (is (eq (mud:room-get-exit room1 "north") room2))
    (is (eq (mud:room-get-exit room2 "south") room1))))

(test print-object-mud-object
      "Test print-object for mud-object"
      (let* ((obj (mud:new-object :name "Test Object"))
             (out (with-output-to-string (s) (print-object obj s))))
        (is (string-equal (format nil "#<MUD:MUD-OBJECT Test Object (ID: ~D)>" (mud:object-id obj))
                          out))))

(test print-object-mud-room
  "Test print-object for mud-room"
  (let ((room (mud:new-room :name "Test Room")))
    (is (string-equal
         (format nil "#<MUD:MUD-ROOM Test Room (ID: ~D)>" (mud:object-id room))
         (with-output-to-string (s) (print-object room s))))))
