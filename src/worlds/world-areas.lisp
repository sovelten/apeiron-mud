;;;; src/worlds/world-areas.lisp — Pre-built transient world areas
;;;;
;;;; These builder functions create the transient room/NPC layout for the
;;;; Apeiron world: the hub biomes, Desert Oasis Mall, and the Team Rocket
;;;; cavern maze.  Call INITIAL-WORLD to produce a mud-world that can then
;;;; be materialized into a persistent-world via APEIRON.PERSISTENCE:MATERIALIZE-WORLD.

(in-package #:apeiron.worlds)

;; ─── Helpers ─────────────────────────────────────────────────────────────────

(defun register-room (world room)
  (world-add-object! world room))

(defun register-npc (world room npc)
  (container-add-object room npc)
  (world-add-object! world npc))

(defun set-flag-gate (room exit-direction flag &optional message)
  (object-set-property room (format nil "gate-~A" (string-downcase exit-direction)) flag)
  (when message
    (object-set-property room
                         (format nil "gate-~A-message" (string-downcase exit-direction))
                         message)))

;; ─── Desert Oasis Mall ───────────────────────────────────────────────────────

(defun build-team-rocket-cavern (world)
  "Build the Team Rocket cavern maze with fights and challenges."
  (let* ((entrance (new-room
                    :name "Team Rocket Cavern Mouth"
                    :description
                    "You squeeze through the maintenance hatch into a rough-hewn cavern. A crimson 'R' is spray-painted on the wall. Distant voices chant 'Prepare for trouble!' echo off the stone."))
         (crossroads (new-room
                      :name "Cavern Crossroads"
                      :description
                      "Three tunnels branch off here. Faint footprints and discarded candy wrappers mark the paths. A scratched sign reads: 'Trespassers will be recruited!'."))
         (grunt-patrol (new-room
                        :name "Grunt Patrol Route"
                        :description
                        "A narrow patrol corridor lit by flickering torches. Pallets of stolen goods are stacked against the walls."))
         (riddle-gallery (new-room
                          :name "Riddle Gallery"
                          :description
                          "Portraits of villainous-looking cats and snakes line the walls. A plaque reads: 'Speak the name of the coin-loving feline to proceed east.'"))
         (cat-alley (new-room
                     :name "Cat Alley"
                     :description
                     "A dead-end alcove with a bronze Meowth statue. It glares at you with gem eyes. 'I'm not saying anything,' it seems to say."))
         (mirror-maze (new-room
                       :name "Mirror Maze"
                       :description
                       "Reflective panels create endless copies of you. Every turn looks the same. Only one path leads onward."))
         (elite-patrol (new-room
                        :name "Elite Patrol Post"
                        :description
                        "This checkpoint is heavily guarded. A chalkboard lists 'Today's Evil Plan: Steal ALL the rare candies.'"))
         (password-gate (new-room
                         :name "Password Gate"
                         :description
                         "A steel door blocks the north tunnel. A keypad blinks beside a note: 'Enter the organization password to proceed.'"))
         (hidden-lab (new-room
                      :name "Hidden Lab"
                      :description
                      "Abandoned lab equipment and broken Poké Ball molds litter this side chamber. Someone left a half-eaten donut on a centrifuge."))
         (boss-chamber (new-room
                        :name "Boss G's Chamber"
                        :description
                        "A vast cavern with a raised platform. Boss G stands with arms crossed, a Persian at his feet. 'So you've made it this far, brat,' he sneers."))
         (treasure (new-room
                    :name "Rocket Treasure Vault"
                    :description
                    "Gold coins, rare candies, and a golden 'R' badge glint in the torchlight. A banner reads: 'Congratulations — you ruined our entire operation!'."))
         (grunt (new-npc
                 :name "a Team Rocket grunt"
                 :description "A uniformed goon in a white W and black R cap."
                 :hp 15 :max-hp 15
                 :attack-min 3 :attack-max 6
                 :defeat-message "The grunt drops a handful of coins and flees, yelling 'We're blasting off again!'"
                 :victory-flag "beat-grunt-1"))
         (elite (new-npc
                 :name "an elite Rocket agent"
                 :description "A smug agent with mirrored shades and a stolen Master Ball on his belt."
                 :hp 25 :max-hp 25
                 :attack-min 5 :attack-max 9
                 :defeat-message "The elite agent stumbles backward. 'Impossible! Boss G will hear about this!'"
                 :victory-flag "beat-elite"))
         (boss (new-npc
                :name "Boss G"
                :description "The infamous leader of this shady outfit, stroking his Persian."
                :hp 45 :max-hp 45
                :attack-min 7 :attack-max 12
                :defeat-message "Boss G crumples. 'This isn't over... I'll be back... with a better evil plan!' The cavern rumbles as secret exits open."
                :victory-flag "beat-boss-g")))
    ;; Maze layout
    (connect-rooms! world entrance "north" crossroads "south")
    (connect-rooms! world crossroads "north" grunt-patrol "south")
    (connect-rooms! world crossroads "east" riddle-gallery "west")
    (connect-rooms! world crossroads "west" mirror-maze "east")
    (connect-rooms! world crossroads "south" cat-alley "north")
    (connect-rooms! world grunt-patrol "north" elite-patrol "south")
    (connect-rooms! world riddle-gallery "east" password-gate "west")
    (connect-rooms! world mirror-maze "south" crossroads "north")
    (connect-rooms! world mirror-maze "west" hidden-lab "east")
    (connect-rooms! world elite-patrol "north" password-gate "south")
    (connect-rooms! world password-gate "north" boss-chamber "south")
    (connect-rooms! world boss-chamber "north" treasure "south")

    ;; Challenges
    (connection-set-challenge (connection-find riddle-gallery "east")
                        "A voice echoes: 'What feline crook loves coins above all else?' Try: answer <name>"
                        "meowth"
                        "solved-meowth-riddle")
    (connection-set-challenge (connection-find password-gate "north")
                        "The keypad demands: 'Enter the organization password.' Try: answer <password>"
                        "rocket"
                        "solved-rocket-password")

    ;; Fight gates
    (set-flag-gate grunt-patrol "north" "beat-grunt-1"
                   "The grunt blocks the north tunnel. Defeat them first! Try: attack grunt")
    (set-flag-gate elite-patrol "north" "beat-elite"
                   "The elite agent stands firm. Try: attack agent")
    (set-flag-gate boss-chamber "north" "beat-boss-g"
                   "Boss G laughs. 'Defeat me first, child!' Try: attack boss")

    ;; NPC placement
    (register-npc world grunt-patrol grunt)
    (register-npc world elite-patrol elite)
    (register-npc world boss-chamber boss)

    (register-room world entrance)
    (register-room world crossroads)
    (register-room world grunt-patrol)
    (register-room world riddle-gallery)
    (register-room world cat-alley)
    (register-room world mirror-maze)
    (register-room world elite-patrol)
    (register-room world password-gate)
    (register-room world hidden-lab)
    (register-room world boss-chamber)
    (register-room world treasure)
    entrance))

(defun build-shopping-mall (world desert)
  "Add the Desert Oasis Mall, linked from the desert via a shimmering door."
  (let* ((door-flavor " A shimmering glass door materializes from the heat haze — frosted letters read 'DESERT OASIS MALL'.")
         (mall (new-room
                :name "Desert Oasis Mall"
                :description
                "A gleaming air-conditioned shopping mall defies the desert outside. Escalators hum, pop music echoes off polished tile, and neon signs advertise everything from potions to plush monsters. Shoppers wander between kiosks while a fountain burbles in the centre."))
         (food-court (new-room
                      :name "Food Court"
                      :description
                      "Rows of fast-food counters line this open plaza. The smell of fried Magikarp sticks and berry smoothies fills the air. Picnic tables are packed with tired trainers on lunch break."))
         (arcade (new-room
                  :name "Arcade Zone"
                  :description
                  "Flashing cabinets and claw machines dominate this wing. A 'Team Rocket Cavern Adventure' ride sits behind a velvet rope — a maintenance hatch beside it is slightly ajar, leaking cold underground air."))
         (fashion (new-room
                   :name "Fashion Wing"
                   :description
                   "Mannequins display the latest trainer gear: cargo shorts, fingerless gloves, and hats that somehow never fall off during battle. A sale banner screams '50% OFF REPEL!'.")))
    (setf (object-description desert)
          (concatenate 'string (object-description desert) door-flavor))
    (connect-rooms! world desert "door" mall "desert")
    (connect-rooms! world mall "north" food-court "south")
    (connect-rooms! world mall "east" arcade "west")
    (connect-rooms! world mall "west" fashion "east")
    (connect-rooms! world arcade "maintenance" (build-team-rocket-cavern world) "mall")
    (dolist (room (list mall food-court arcade fashion))
      (register-room world room))
    mall))

(defun new-default-world ()
  "Create the default Apeiron world with all areas (hub, mall, cavern)."
  (let ((world (make-instance 'mud-world)))
    (let ((gathering (new-room :name "The Gathering"
                                          :description "A warm, circular hall with a high domed ceiling. Torches flicker along the stone walls, casting dancing shadows. Four archways stand at the cardinal points, each bearing a carved symbol: a leaf (north), a sun (east), a droplet (west), and a flame (south). A sturdy oak guestbook sits on a pedestal in the centre."))
          (forest (new-room :name "A Whispering Forest"
                                       :description "Ancient trees tower overhead, their leaves rustling secrets in the wind. Shafts of golden sunlight pierce the canopy, illuminating patches of moss and wildflowers. A faint path winds deeper into the woods."))
          (desert (new-room :name "A Sun-Bleached Desert"
                                       :description "Endless dunes of golden sand stretch to the horizon under a blinding sun. The heat shimmers in waves, and the silence is broken only by the occasional skitter of a unseen creature. The bleached bones of a long-dead beast protrude from a nearby dune."))
          (swamp (new-room :name "A Murky Swamp"
                                      :description "Stagnant water laps at gnarled tree roots as thick mist curls around your ankles. The air is heavy with the smell of decay and damp earth. Somewhere in the distance, a bullfrog croaks and something large splashes."))
          (volcano (new-room :name "A Rumbling Volcano"
                                        :description "The ground trembles beneath your feet. Glowing lava flows through cracks in the black, jagged rock, casting an eerie red glow across the cavern. Heat shimmers violently and the air reeks of sulphur. The mountain groans above you."))
          (guestbook (new-guestbook :name "an oak guestbook")))
      ;; Place the guestbook in The Gathering
      (container-add-object gathering guestbook)
      ;; Connect The Gathering (hub) to the four biomes
      (connect-rooms! world gathering "north" forest "south")
      (connect-rooms! world gathering "east" desert "west")
      (connect-rooms! world gathering "west" swamp "east")
      (connect-rooms! world gathering "south" volcano "north")
      ;; Desert door → shopping mall → Team Rocket cavern maze
      (build-shopping-mall world desert)
      ;; Register all objects in the world
      (world-add-object! world guestbook)
      (world-add-object! world gathering)
      (world-add-object! world forest)
      (world-add-object! world desert)
      (world-add-object! world swamp)
      (world-add-object! world volcano)
      (world-set-starting-room! world gathering))
    world))
