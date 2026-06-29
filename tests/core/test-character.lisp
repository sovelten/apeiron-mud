(in-package #:apeiron-test)

(in-suite core-suite)

(test player-creation
  "Test that we can create a player"
  (apeiron.persistence:world-restore-or-initialize)
  (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
    (is (equal (apeiron.core:object-name player) "TestPlayer"))
    (is (typep player 'apeiron.core:mud-character))
    (is (hash-table-p (apeiron.core:container-contents player)))))

(test player-inventory
  "Test player inventory management"
  (apeiron.persistence:world-restore-or-initialize)
  (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
        (obj (apeiron.core:new-room :name "Test Item")))
    (apeiron.core:container-add-object player obj)
    (is (= 1 (hash-table-count (apeiron.core:container-contents player))))
    (is (eq obj (apeiron.core:container-object-by-id player (apeiron.core:object-id obj))))
    (apeiron.core:container-remove-object player obj)
    (is (= 0 (hash-table-count (apeiron.core:container-contents player))))))

(test player-location
  "Test that player has a location"
  (let ((world (apeiron.persistence:world-restore-or-initialize))
        (player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
    (apeiron.core:world-add-character! world player)
    (is (not (null (apeiron.core:object-location player))))
    (is (typep (apeiron.core:object-location player) 'apeiron.core:mud-room))))
