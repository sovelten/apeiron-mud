(in-package #:mud.tests)

(in-suite mud-tests)

(test player-creation
  "Test that we can create a player"
  (mud:world-restore-or-initialize)
  (let ((player (mud:new-character "TestPlayer" (make-instance 'mud:mud-session :socket nil))))
    (is (equal (mud:object-name player) "TestPlayer"))
    (is (typep player 'mud:mud-character))
    (is (vectorp (mud:player-inventory player)))))

(test player-inventory
  "Test player inventory management"
  (mud:world-restore-or-initialize)
  (let ((player (mud:new-character "TestPlayer" (make-instance 'mud:mud-session :socket nil)))
        (obj (mud:new-room :name "Test Item")))
    (mud:character-inventory-add player obj)
    (is (> (length (mud:player-inventory player)) 0))
    (is (equal (aref (mud:player-inventory player) 0) obj))
    (mud:character-inventory-remove player obj)
    (is (= (length (mud:player-inventory player)) 0))))

(test player-location
  "Test that player has a location"
  (mud:world-restore-or-initialize)
  (let ((player (mud:new-character "TestPlayer" (make-instance 'mud:mud-session :socket nil))))
    (mud:world-new-character player)
    (is (not (null (mud:object-location player))))
    (is (typep (mud:object-location player) 'mud:mud-room))))
