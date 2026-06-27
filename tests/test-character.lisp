(in-package #:mud-test)

(in-suite mud-tests)

(test player-creation
  "Test that we can create a player"
  (apeiron.persistence:world-restore-or-initialize)
  (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
    (is (equal (apeiron.core:object-name player) "TestPlayer"))
    (is (typep player 'apeiron.core:mud-character))
    (is (vectorp (apeiron.core:player-inventory player)))))

(test player-inventory
  "Test player inventory management"
  (apeiron.persistence:world-restore-or-initialize)
  (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil)))
        (obj (apeiron.core:new-room :name "Test Item")))
    (apeiron.core:character-inventory-add player obj)
    (is (> (length (apeiron.core:player-inventory player)) 0))
    (is (equal (aref (apeiron.core:player-inventory player) 0) obj))
    (apeiron.core:character-inventory-remove player obj)
    (is (= (length (apeiron.core:player-inventory player)) 0))))

(test player-location
  "Test that player has a location"
  (let ((world (apeiron.persistence:world-restore-or-initialize))
        (player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
    (apeiron.core:world-add-character! world player)
    (is (not (null (apeiron.core:object-location player))))
    (is (typep (apeiron.core:object-location player) 'apeiron.core:mud-room))))
