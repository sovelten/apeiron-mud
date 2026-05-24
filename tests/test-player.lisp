(in-package #:mud.tests)

(in-suite mud-tests)

(test player-creation
  "Test that we can create a player"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil)))
    (is (equal (mud:object-name player) "TestPlayer"))
    (is (typep player 'mud:mud-player))
    (is (vectorp (mud:player-inventory player)))))

(test player-inventory
  "Test player inventory management"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil))
        (obj (mud:create-object :name "Test Item")))
    (mud:player-inventory-add player obj)
    (is (> (length (mud:player-inventory player)) 0))
    (is (equal (aref (mud:player-inventory player) 0) obj))
    (mud:player-inventory-remove player obj)
    (is (= (length (mud:player-inventory player)) 0))))

(test player-location
  "Test that player has a location"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil)))
    (is (not (null (mud:object-location player))))
    (is (typep (mud:object-location player) 'mud:mud-room))))

(test player-in-room
  "Test that player is added to room on creation"
  (mud:world-initialize)
  (let* ((player (mud:create-player "TestPlayer" nil))
         (room (mud:object-location player))
         (contents (mud:room-contents room)))
    (is (not (null room)))
    (is (vectorp contents))
    (is (> (length contents) 0))
    (is (find player contents))))
