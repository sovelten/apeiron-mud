;;;; src/worlds/world-areas.lisp — Pre-built transient world areas
;;;;
;;;; These builder functions create the transient room/NPC layout for the
;;;; Apeiron world as MUD-AREA objects: the Apeiron Hub biomes, the Desert
;;;; Oasis Mall, and the Team Rocket cavern maze.  Each builder returns a
;;;; self-contained MUD-AREA; NEW-DEFAULT-WORLD registers them in a
;;;; mud-world via WORLD-ADD-AREA! and wires the cross-area connections.
;;;; The result can then be materialized into a persistent-world via
;;;; APEIRON.PERSISTENCE:MATERIALIZE-WORLD.

(in-package #:apeiron.worlds)

;; ─── Helpers ─────────────────────────────────────────────────────────────────

(defun set-flag-gate (room exit-direction flag &optional message)
  "Set a flag-based gate on ROOM: the EXIT-DIRECTION is blocked until the
character has FLAG.  MESSAGE is shown when they try to pass."
  (object-set-property room (format nil "gate-~A" (string-downcase exit-direction)) flag)
  (when message
    (object-set-property room
                         (format nil "gate-~A-message" (string-downcase exit-direction))
                         message)))

;; ─── Team Rocket Cavern ──────────────────────────────────────────────────────

(defun build-team-rocket-cavern ()
  "Build the Team Rocket cavern maze as a MUD-AREA with fights and
challenges.  The area's entrance is the cavern mouth.  Returns the area."
  (let ((area (new-area :name "Team Rocket Cavern")))
    (let* ((entrance (new-room
                      :name "Team Rocket Cavern Mouth"
                      :description
                      "You squeeze through the maintenance hatch into a rough-hewn cavern. A crimson 'R' is spray-painted on the wall. Distant voices chant 'Prepare for trouble!' echo off the stone."))
           (crossroads (new-room
                        :name "Cavern Crossroads"
                        :description
                        "Three tunnels branch south, east, and west from this intersection. The rough-hewn passage you entered from lies to the north. Faint footprints and discarded candy wrappers mark the paths. A scratched sign reads: 'Trespassers will be recruited!'."))
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
      ;; Layout (north=up, south=down, east=right, west=left):
      ;;
      ;;               entrance
      ;;                  │
      ;;          west    │
      ;;    mirror-maze ──┼
      ;;                  │
      ;;           ┌──────┴──────┐
      ;;           │  Crossroads │──── east ────▶ riddle-gallery ── south ──▶ cat-alley
      ;;           └──────┬──────┘                                     (meowth riddle)  (Meowth statue)
      ;;                  │ south
      ;;           ┌──────┴──────┐
      ;;           │    Grunt    │
      ;;           │   Patrol    │
      ;;           └──────┬──────┘
      ;;                  │ south (beat-grunt-1)
      ;;           ┌──────┴──────┐
      ;;           │    Elite    │
      ;;           │   Patrol    │
      ;;           └──────┬──────┘
      ;;                  │ south (beat-elite)
      ;;           ┌──────┴──────┐
      ;;           │  Password   │
      ;;           │    Gate     │
      ;;           └──────┬──────┘
      ;;                  │ south (org password)
      ;;           ┌──────┴──────┐
      ;;           │  Boss G's   │
      ;;           │   Chamber   │
      ;;           └──────┬──────┘
      ;;                  │ south (beat-boss-g)
      ;;           ┌──────┴──────┐
      ;;           │  Treasure   │
      ;;           │   Vault     │
      ;;           └─────────────┘
      ;; entrance
      (area-connect-north-south! area entrance crossroads)
      ;; go west to mirror-maze
      (area-connect-west-east! area mirror-maze crossroads)
      ;; go west from mirror-maze to hidden-lab
      (area-connect-west-east! area hidden-lab mirror-maze)
      ;; go south from crossroads to grunt-patrol
      (area-connect-north-south! area crossroads grunt-patrol)
      ;; go south from grunt-patrol to elite-patrol
      (area-connect-north-south! area grunt-patrol elite-patrol)
      ;; go east from crossroads to riddle-gallery
      (area-connect-west-east! area crossroads riddle-gallery)
      ;; go south from riddle-gallery to cat-alley
      (area-connect-north-south! area riddle-gallery cat-alley)
      ;; go south from elite-patrol to password-gate
      (area-connect-north-south! area elite-patrol password-gate)
      ;; go south from password-gate to boss-chamber
      (area-connect-north-south! area password-gate boss-chamber)
      ;; go south from boss-chamber to treasure
      (area-connect-north-south! area boss-chamber treasure)

      ;; Challenges
      (connection-set-challenge (connection-find riddle-gallery "south")
                                "A voice echoes: 'What feline crook loves coins above all else?' Try: answer <name>"
                                "meowth"
                                "solved-meowth-riddle")
      (connection-set-challenge (connection-find password-gate "south")
                                "The keypad demands: 'Enter the organization password.' Try: answer <password>"
                                "rocket"
                                "solved-rocket-password")

      ;; Fight gates
      (set-flag-gate grunt-patrol "south" "beat-grunt-1"
                     "The grunt blocks the south tunnel. Defeat them first! Try: attack grunt")
      (set-flag-gate elite-patrol "south" "beat-elite"
                     "The elite agent stands firm. Try: attack agent")
      (set-flag-gate boss-chamber "south" "beat-boss-g"
                     "Boss G laughs. 'Defeat me first, child!' Try: attack boss")

      ;; NPC placement
      (container-add-object grunt-patrol grunt)
      (container-add-object elite-patrol elite)
      (container-add-object boss-chamber boss)

      (area-set-entrance! area entrance)
      area)))

;; ─── Desert Oasis Mall ───────────────────────────────────────────────────────

(defun build-shopping-mall ()
  "Build the Desert Oasis Mall as a MUD-AREA.  The area's entrance is the
main concourse.  Returns the area."
  (let ((area (new-area :name "Desert Oasis Mall")))
    (let ((mall (new-room
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
      (area-connect-north-south! area mall food-court)
      (area-connect-west-east! area mall arcade)
      (area-connect-west-east! area fashion mall)
      (area-set-entrance! area mall)
      area)))

;; ─── Apeiron Hub ─────────────────────────────────────────────────────────────

(defun build-apeiron-hub ()
  "Build the Apeiron Hub area: the nexus, the four biome rooms, and the
guestbook (placed in the nexus).  The area's entrance is the nexus.
Returns the area."
  (let* ((nexus (new-room :name "Apeiron Nexus"
                          :description "You are in a place outside of time and space. All possibilities and all things conjoin here. You can go everywhere, do everything. Be everything. What will you do?"))
         (forest (new-room :name "Puzzling Forest"
                           :description "Ancient trees tower overhead, their leaves rustling secrets in the wind. Shafts of golden sunlight pierce the canopy, illuminating patches of moss and wildflowers. A faint path winds deeper into the woods."))
         (desert (new-room :name "A Sun-Bleached Desert"
                           :description "Endless dunes of golden sand stretch to the horizon under a blinding sun. The heat shimmers in waves, and the silence is broken only by the occasional skitter of a unseen creature. The bleached bones of a long-dead beast protrude from a nearby dune."))
         (swamp (new-room :name "A Murky Swamp"
                          :description "Stagnant water laps at gnarled tree roots as thick mist curls around your ankles. The air is heavy with the smell of decay and damp earth. Somewhere in the distance, a bullfrog croaks and something large splashes."))
         (volcano (new-room :name "A Rumbling Volcano"
                            :description "The ground trembles beneath your feet. Glowing lava flows through cracks in the black, jagged rock, casting an eerie red glow across the cavern. Heat shimmers violently and the air reeks of sulphur. The mountain groans above you."))
         (guestbook (new-guestbook :name "an oak guestbook"))
         (area (new-area :name "Apeiron Hub")))
    ;; Place the guestbook in the nexus
    (container-add-object nexus guestbook)
    ;; Connect the nexus (hub) to the four biomes
    ;; Forest uses a custom named connection: "Puzzling Forest" with synonym "pf"
    (area-connect-rooms! area nexus forest
                         :to '("Puzzling Forest" "pf") :from "nexus")
    (area-connect-west-east! area nexus desert)
    (area-connect-west-east! area swamp nexus)
    (area-connect-north-south! area nexus volcano)
    (area-set-entrance! area nexus)
    area))

;; ─── Default world ───────────────────────────────────────────────────────────

(defun new-default-world ()
  "Create the default Apeiron world with all areas (hub, mall, cavern),
registered via WORLD-ADD-AREA! and linked to one another.  Each area's
entrance is used for the cross-area links and the world's starting room."
  (let ((world (make-instance 'mud-world)))
    (let ((hub (build-apeiron-hub))
          (mall (build-shopping-mall))
          (cavern (build-team-rocket-cavern)))
      (world-add-area! world hub)
      (world-add-area! world mall)
      (world-add-area! world cavern)
      ;; Cross-area links
      (let ((desert (area-find-room hub "A Sun-Bleached Desert")))
        (setf (object-description desert)
              (concatenate 'string (object-description desert)
                           " A shimmering glass door materializes from the heat haze — frosted letters read 'DESERT OASIS MALL'."))
        ;; Desert door → shopping mall
        (connect-rooms! world desert (area-entrance mall) :to "door" :from "desert")
        ;; Mall arcade → Team Rocket cavern maze
        (connect-rooms! world (area-find-room mall "Arcade Zone") (area-entrance cavern)
                        :to "maintenance" :from "mall")
        ;; Players start at the hub's entrance
        (world-set-starting-room! world (area-entrance hub))))
    world))
