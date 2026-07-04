;;;; tests/worlds/test-world-areas.lisp — Tests for pre-built world areas.
;;;;
;;;; Exercises the Desert Oasis Mall and Team Rocket cavern maze layouts,
;;;; NPC placement, combat mechanics, and riddle/password gates.

(in-package #:apeiron-test)

(in-suite worlds-suite)

(test shopping-mall-from-desert
  "Desert has a door exit to the shopping mall."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (all-rooms (apeiron.core:world-all-rooms world))
         (desert (find-if (lambda (r) (search "Sun-Bleached" (apeiron.core:object-name r)))
                          all-rooms)))
    (is (not (null desert)))
    (is (not (null (apeiron.core:room-exit-target desert "door"))))
    (is (search "DESERT OASIS MALL" (apeiron.core:object-description desert)))))

(test team-rocket-cavern-maze
  "Arcade connects to Team Rocket cavern with NPCs and challenges."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (all-rooms (apeiron.core:world-all-rooms world))
         (arcade (find-if (lambda (r) (string= "Arcade Zone" (apeiron.core:object-name r))) all-rooms))
         (entrance (find-if (lambda (r) (search "Cavern Mouth" (apeiron.core:object-name r))) all-rooms))
         (grunt-room (find-if (lambda (r) (string= "Grunt Patrol Route" (apeiron.core:object-name r))) all-rooms))
         (npcs (remove-if-not (lambda (obj) (typep obj 'apeiron.core:mud-npc))
                              (apeiron.core:world-all-objects world))))
    (is (not (null arcade)))
    (is (not (null entrance)))
    (is (eq entrance (apeiron.core:room-exit-target arcade "maintenance")))
    (is (>= (length all-rooms) 15))
    (is (>= (length npcs) 3))
    (is (not (null grunt-room)))
    (let ((grunt (find-if (lambda (obj)
                            (and (typep obj 'apeiron.core:mud-npc)
                                 (search "grunt" (string-downcase (apeiron.core:object-name obj)))))
                          (apeiron.core:container-all-objects grunt-room))))
      (is (not (null grunt))))))

(test combat-attack-grunt
  "Player can attack and defeat a grunt."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (player (apeiron.core:new-character "Fighter" (make-instance 'apeiron.core:stream-session
                                                                       :stream (make-string-output-stream))))
         (all-rooms (apeiron.core:world-all-rooms world))
         (grunt-room (find-if (lambda (r) (string= "Grunt Patrol Route" (apeiron.core:object-name r)))
                              all-rooms))
         (grunt (find-if (lambda (obj) (typep obj 'apeiron.core:mud-npc))
                          (apeiron.core:container-all-objects grunt-room))))
    (apeiron.core:object-move player grunt-room)
    (is (not (apeiron.core:npc-defeated-p grunt)))
    (loop repeat 20
          until (apeiron.core:npc-defeated-p grunt)
          do (apeiron.core:combat-attack-npc world player grunt))
    (is (apeiron.core:npc-defeated-p grunt))
    (is (apeiron.core:object-get-property player "beat-grunt-1"))))

(test player-defeated-respawns-at-cavern-mouth
  "When a player is knocked out by an NPC, they respawn at the cavern mouth
   without error — regression test: world-rooms returns a hash-table, not a list."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (player (apeiron.core:new-character "Fighter" (make-instance 'apeiron.core:stream-session
                                                                       :stream (make-string-output-stream))))
         (all-rooms (apeiron.core:world-all-rooms world))
         (grunt-room (find-if (lambda (r) (string= "Grunt Patrol Route" (apeiron.core:object-name r)))
                              all-rooms))
         (grunt (find-if (lambda (obj) (typep obj 'apeiron.core:mud-npc))
                          (apeiron.core:container-all-objects grunt-room))))
    ;; Put the player in the grunt room
    (apeiron.core:object-move player grunt-room)
    ;; Crank the player's HP down so the very first counter-attack KOs them
    (setf (apeiron.core:player-hp player) 1)
    ;; This call triggers the respawn code path (player-defeated-p → world-rooms)
    ;; It should not signal a type-error
    (is (listp (apeiron.core:combat-attack-npc world player grunt)))
    ;; After defeat, player should be healed and not in the grunt room
    (is (> (apeiron.core:player-hp player) 0))
    (is (not (eq (apeiron.core:object-location player) grunt-room)))))

(test challenge-answer-riddle
  "Answering a riddle unlocks the challenge flag."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (player (apeiron.core:new-character "Solver" (make-instance 'apeiron.core:stream-session
                                                                      :stream (make-string-output-stream))))
         (all-rooms (apeiron.core:world-all-rooms world))
         (gallery (find-if (lambda (r) (string= "Riddle Gallery" (apeiron.core:object-name r)))
                           all-rooms)))
    (apeiron.core:object-move player gallery)
    (is (not (null (apeiron.core:room-challenge-blocked-p gallery player "east"))))
    (apeiron.core:object-set-property player "solved-meowth-riddle" t)
    (is (null (apeiron.core:room-challenge-blocked-p gallery player "east")))))
