;;;; tests/worlds/test-world-areas.lisp — Tests for pre-built world areas.
;;;;
;;;; Exercises the Desert Oasis Mall and Team Rocket cavern maze layouts,
;;;; NPC placement, combat mechanics, and riddle/password gates.

(in-package #:apeiron-test)

(in-suite worlds-suite)

(test shopping-mall-from-desert
  "The nexus has a 'Poké Land' (pl) portal exit to the shopping mall."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (all-rooms (apeiron.core:world-all-rooms world))
         (nexus (apeiron.core:starting-room world))
         (mall (find-if (lambda (r) (string= "Desert Oasis Mall" (apeiron.core:object-name r)))
                        all-rooms)))
    (is (not (null nexus)))
    (is (not (null mall)))
    (is (eq mall (apeiron.core:room-exit-target nexus "Poké Land")))
    (is (eq mall (apeiron.core:room-exit-target nexus "pl")))
    (is (eq nexus (apeiron.core:room-exit-target mall "nexus")))))

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
  "Character can attack and defeat a grunt."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (character (apeiron.core:new-character "Fighter" (make-instance 'apeiron.core:stream-session
                                                                       :stream (make-string-output-stream))))
         (all-rooms (apeiron.core:world-all-rooms world))
         (grunt-room (find-if (lambda (r) (string= "Grunt Patrol Route" (apeiron.core:object-name r)))
                              all-rooms))
         (grunt (find-if (lambda (obj) (typep obj 'apeiron.core:mud-npc))
                          (apeiron.core:container-all-objects grunt-room))))
    (apeiron.core:object-move character grunt-room)
    (is (not (apeiron.core:npc-defeated-p grunt)))
    (loop repeat 20
          until (apeiron.core:npc-defeated-p grunt)
          do (apeiron.core:combat-attack-npc world character grunt))
    (is (apeiron.core:npc-defeated-p grunt))
    (is (apeiron.core:object-get-property character "beat-grunt-1"))))

(test character-defeated-respawns-at-cavern-mouth
  "When a character is knocked out by an NPC, they respawn at the cavern mouth
   without error — regression test: world-rooms returns a hash-table, not a list."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (character (apeiron.core:new-character "Fighter" (make-instance 'apeiron.core:stream-session
                                                                       :stream (make-string-output-stream))))
         (all-rooms (apeiron.core:world-all-rooms world))
         (grunt-room (find-if (lambda (r) (string= "Grunt Patrol Route" (apeiron.core:object-name r)))
                              all-rooms))
         (grunt (find-if (lambda (obj) (typep obj 'apeiron.core:mud-npc))
                          (apeiron.core:container-all-objects grunt-room))))
    ;; Put the character in the grunt room
    (apeiron.core:object-move character grunt-room)
    ;; Crank the character's HP down so the very first counter-attack KOs them
    (setf (apeiron.core:character-hp character) 1)
    ;; This call triggers the respawn code path (character-defeated-p → world-rooms)
    ;; It should not signal a type-error
    (is (listp (apeiron.core:combat-attack-npc world character grunt)))
    ;; After defeat, character should be healed and not in the grunt room
    (is (> (apeiron.core:character-hp character) 0))
    (is (not (eq (apeiron.core:object-location character) grunt-room)))))

(test challenge-answer-riddle
  "Answering a riddle correctly unblocks the connection via process-command."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (stream (make-string-output-stream))
         (character (apeiron.core:new-character "Solver" (make-instance 'apeiron.core:stream-session
                                                                      :stream stream)))
         (all-rooms (apeiron.core:world-all-rooms world))
         (gallery (find-if (lambda (r) (string= "Riddle Gallery" (apeiron.core:object-name r)))
                           all-rooms)))
    (apeiron.core:object-move character gallery)
    ;; Exit should be blocked before answering
    (is (not (null (apeiron.core:room-exit-blocked-p gallery character "south"))))
    (is (search "feline" (apeiron.core:room-exit-blocked-p gallery character "south")))
    ;; Character answers correctly via the command system
    (apeiron.core:process-command world character "answer meowth")
    ;; Exit should now be unblocked
    (is (null (apeiron.core:room-exit-blocked-p gallery character "east")))
    ;; Character's flag should be set
    (is (apeiron.core:object-get-property character "solved-meowth-riddle"))))

(test default-world-areas
  "The default world is organized into three areas (hub, mall, cavern),
  each room belongs to exactly one area, and cross-area links work."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world)))
    (is (= 3 (apeiron.core:world-total-areas world)))
    (let ((hub (apeiron.core:world-area-with-name world "Apeiron Hub"))
          (mall (apeiron.core:world-area-with-name world "Desert Oasis Mall"))
          (cavern (apeiron.core:world-area-with-name world "Team Rocket Cavern")))
      (is (not (null hub)))
      (is (not (null mall)))
      (is (not (null cavern)))
      (is (= 4 (apeiron.core:area-room-count hub)))
      (is (= 4 (apeiron.core:area-room-count mall)))
      (is (= 11 (apeiron.core:area-room-count cavern)))
      ;; world-area-of-room resolves each room to exactly one area
      (is (eq hub (apeiron.core:world-area-of-room
                   world (apeiron.core:area-find-room hub "Apeiron Nexus"))))
      (is (eq mall (apeiron.core:world-area-of-room
                    world (apeiron.core:area-find-room mall "Arcade Zone"))))
      (is (eq cavern (apeiron.core:world-area-of-room
                      world (apeiron.core:area-find-room cavern "Grunt Patrol Route"))))
      ;; areas do not share rooms
      (is (null (intersection (apeiron.core:area-room-list hub)
                              (apeiron.core:area-room-list mall))))
      (is (null (intersection (apeiron.core:area-room-list mall)
                              (apeiron.core:area-room-list cavern))))
      ;; cross-area links survived the area-based build
      (let ((nexus (apeiron.core:area-find-room hub "Apeiron Nexus")))
        (is (eq (apeiron.core:area-find-room mall "Desert Oasis Mall")
                (apeiron.core:room-exit-target nexus "pl"))))
      (let ((arcade (apeiron.core:area-find-room mall "Arcade Zone")))
        (is (eq (apeiron.core:area-find-room cavern "Team Rocket Cavern Mouth")
                (apeiron.core:room-exit-target arcade "maintenance")))))))
