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
  "The default world is organized into four areas (hub, mall, cavern,
  eridu), each room belongs to exactly one area, and cross-area links work."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world)))
    (is (= 4 (apeiron.core:world-total-areas world)))
    (let ((hub (apeiron.core:world-area-with-name world "Apeiron Hub"))
          (mall (apeiron.core:world-area-with-name world "Desert Oasis Mall"))
          (cavern (apeiron.core:world-area-with-name world "Team Rocket Cavern"))
          (eridu (apeiron.core:world-area-with-name world "Eridu, the First City")))
      (is (not (null hub)))
      (is (not (null mall)))
      (is (not (null cavern)))
      (is (not (null eridu)))
      (is (= 4 (apeiron.core:area-room-count hub)))
      (is (= 4 (apeiron.core:area-room-count mall)))
      (is (= 11 (apeiron.core:area-room-count cavern)))
      (is (= 18 (apeiron.core:area-room-count eridu)))
      ;; world-area-of-room resolves each room to exactly one area
      (is (eq hub (apeiron.core:world-area-of-room
                   world (apeiron.core:area-find-room hub "Apeiron Nexus"))))
      (is (eq mall (apeiron.core:world-area-of-room
                    world (apeiron.core:area-find-room mall "Arcade Zone"))))
      (is (eq cavern (apeiron.core:world-area-of-room
                      world (apeiron.core:area-find-room cavern "Grunt Patrol Route"))))
      (is (eq eridu (apeiron.core:world-area-of-room
                     world (apeiron.core:area-find-room eridu "Marsh Causeway"))))
      ;; areas do not share rooms
      (is (null (intersection (apeiron.core:area-room-list hub)
                              (apeiron.core:area-room-list mall))))
      (is (null (intersection (apeiron.core:area-room-list mall)
                              (apeiron.core:area-room-list cavern))))
      (is (null (intersection (apeiron.core:area-room-list cavern)
                              (apeiron.core:area-room-list eridu))))
      ;; cross-area links survived the area-based build
      (let ((nexus (apeiron.core:area-find-room hub "Apeiron Nexus")))
        (is (eq (apeiron.core:area-find-room mall "Desert Oasis Mall")
                (apeiron.core:room-exit-target nexus "pl")))
        (is (eq (apeiron.core:area-find-room eridu "Marsh Causeway")
                (apeiron.core:room-exit-target nexus "Eridu")))
        (is (eq (apeiron.core:area-find-room eridu "Marsh Causeway")
                (apeiron.core:room-exit-target nexus "ed"))))
      (let ((arcade (apeiron.core:area-find-room mall "Arcade Zone")))
        (is (eq (apeiron.core:area-find-room cavern "Team Rocket Cavern Mouth")
                (apeiron.core:room-exit-target arcade "maintenance")))))))

(test eridu-first-city
  "Eridu, the first city of Sumer, is reachable from the nexus, contains
  the full temple precinct, and its riddles and fight-gates work."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t
                 :initializer #'apeiron.worlds:new-default-world))
         (all-rooms (apeiron.core:world-all-rooms world))
         (nexus (apeiron.core:starting-room world))
         (eridu (apeiron.core:world-area-with-name world "Eridu, the First City"))
         (causeway (apeiron.core:area-find-room eridu "Marsh Causeway"))
         (market (apeiron.core:area-find-room eridu "Market Square of Eridu"))
         (e-abzu (apeiron.core:area-find-room eridu "E-Abzu, Temple of Enki"))
         (npcs (remove-if-not (lambda (obj) (typep obj 'apeiron.core:mud-npc))
                              (apeiron.core:world-all-objects world))))
    ;; The nexus portal leads to Eridu's entrance
    (is (not (null eridu)))
    (is (eq causeway (apeiron.core:room-exit-target nexus "Eridu")))
    (is (eq causeway (apeiron.core:room-exit-target nexus "ed")))
    (is (eq nexus (apeiron.core:room-exit-target causeway "nexus")))
    ;; The city is a fully connected area
    (is (= 18 (apeiron.core:area-room-count eridu)))
    (is (apeiron.core:area-connected-graph-p eridu))
    (is (>= (length npcs) 8))
    (is (not (null market)))
    (is (not (null e-abzu)))
    ;; The riddle on the way into the sacred precinct
    (let* ((stream (make-string-output-stream))
           (character (apeiron.core:new-character "Pilgrim" (make-instance 'apeiron.core:stream-session
                                                                         :stream stream))))
      (apeiron.core:object-move character market)
      (is (not (null (apeiron.core:room-exit-blocked-p market character "north"))))
      (apeiron.core:process-command world character "answer eridu")
      (is (null (apeiron.core:room-exit-blocked-p market character "north")))
      (is (apeiron.core:object-get-property character "solved-eridu-riddle")))
    ;; The fight gate into the Abzu: the goat-fish must fall first
    (let* ((stream (make-string-output-stream))
           (character (apeiron.core:new-character "Wanderer" (make-instance 'apeiron.core:stream-session
                                                                           :stream stream))))
      (apeiron.core:object-move character e-abzu)
      (let ((goat (find-if (lambda (obj)
                             (and (typep obj 'apeiron.core:mud-npc)
                                  (search "goat-fish" (string-downcase (apeiron.core:object-name obj)))))
                           (apeiron.core:container-all-objects e-abzu))))
        (is (not (null goat)))
        ;; Blocked until the guardian is defeated
        (is (not (null (apeiron.core:room-exit-blocked-p e-abzu character "north"))))
        (loop repeat 20
              until (apeiron.core:npc-defeated-p goat)
              do (apeiron.core:combat-attack-npc world character goat))
        (is (apeiron.core:npc-defeated-p goat))
        (is (apeiron.core:object-get-property character "beat-suhur-mashu"))
        (is (null (apeiron.core:room-exit-blocked-p e-abzu character "north")))))))

(test eridu-added-at-runtime-to-persistent-world
  "A pre-built area can be added to an already-running persistent world
  at runtime, and survives a snapshot + restart.  Regression test: the
  persistent-world world-add-area! method must materialize rooms before
  the area, otherwise the area's ROOMS slot is encoded into the
  transaction log while its rooms are still transient MUD-ROOMs and BKNR
  fails with 'no applicable method for ENCODE-OBJECT'."
  (unwind-protect
       (let* ((world (apeiron.persistence:world-restore-or-initialize
                      :force-new t
                      :initializer (lambda ()
                                     (let ((w (apeiron.core:new-world)))
                                       (let ((r (apeiron.core:new-room :name "Bare Nexus")))
                                         (apeiron.core:world-add-object! w r)
                                         (apeiron.core:world-set-starting-room! w r))
                                       w))))
              (eridu (apeiron.worlds::build-eridu)))
         ;; Adding a fresh area to the live persistent world must not error.
         ;; The bare initializer world has no areas, so Eridu is the first.
         (is (= 0 (apeiron.core:world-total-areas world)))
         (apeiron.core:world-add-area! world eridu)
         (is (= 1 (apeiron.core:world-total-areas world)))
         (let ((area (apeiron.core:world-area-with-name world "Eridu, the First City")))
           (is (not (null area)))
           (is (typep area 'apeiron.persistence:persistent-area))
           (is (= 18 (apeiron.core:area-room-count area)))
           (is (apeiron.core:area-connected-graph-p area))
           (is (equal "Marsh Causeway"
                      (apeiron.core:object-name (apeiron.core:area-entrance area)))))
         ;; The area must survive a snapshot + restart.
         (apeiron.persistence:sync-world)
         (bknr.datastore:close-store)
         (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
                (restored (apeiron.core:world-area-with-name new-world "Eridu, the First City")))
           (is (not (null restored)))
           (is (= 1 (apeiron.core:world-total-areas new-world)))
           (is (= 18 (apeiron.core:area-room-count restored)))
           (is (apeiron.core:area-connected-graph-p restored))
           (is (equal "Marsh Causeway"
                      (apeiron.core:object-name (apeiron.core:area-entrance restored))))
           ;; name lookups work against the restored graph
           (is (equal "Great Street of Eridu"
                      (apeiron.core:object-name
                       (apeiron.core:area-find-room restored "Great Street of Eridu"))))))
    (ignore-errors
     (when (boundp 'bknr.datastore:*store*)
       (ignore-errors (bknr.datastore:close-store))
       (makunbound 'bknr.datastore:*store*)))))
