;;;; src/worlds/apeiron.lisp — The Apeiron world
;;;;
;;;; Defines the Apeiron Hub and assembles the default world.

(in-package #:apeiron.worlds)

(named-readtables:in-readtable pythonic-string-syntax)

(defsection @apeiron-hub (:title "Apeiron Hub")
  """The Apeiron Hub is the nexus of the game world: the arrival point
  for players and the anchor from which the world unfolds.
  BUILD-APEIRON-HUB constructs the hub as a self-contained MUD-AREA,
  and NEW-DEFAULT-WORLD assembles the complete world from it."""
  (build-apeiron-hub function)
  (new-default-world function))

;; ─── Apeiron Hub ─────────────────────────────────────────────────────────────

(defun build-apeiron-hub ()
  "Build the Apeiron Hub area: the nexus (a hub to other areas/universes),
the biome rooms, and the guestbook (placed in the nexus).  The area's
entrance is the nexus.  Returns the area."
  (let* ((nexus (new-room :name "Apeiron Nexus"
                          :description "You are in a place outside of time and space. All possibilities and all things conjoin here. You can go everywhere, do everything. Be everything. What will you do?"))
         (forest (new-room :name "Puzzling Forest"
                           :description "Ancient trees tower overhead, their leaves rustling secrets in the wind. Shafts of golden sunlight pierce the canopy, illuminating patches of moss and wildflowers. A faint path winds deeper into the woods."))
         (swamp (new-room :name "A Murky Swamp"
                          :description "Stagnant water laps at gnarled tree roots as thick mist curls around your ankles. The air is heavy with the smell of decay and damp earth. Somewhere in the distance, a bullfrog croaks and something large splashes."))
         (volcano (new-room :name "A Rumbling Volcano"
                            :description "The ground trembles beneath your feet. Glowing lava flows through cracks in the black, jagged rock, casting an eerie red glow across the cavern. Heat shimmers violently and the air reeks of sulphur. The mountain groans above you."))
         (guestbook (new-guestbook :name "an oak guestbook"))
         (area (new-area :name "Apeiron Hub")))
    ;; Place the guestbook in the nexus
    (container-add-object nexus guestbook)
    ;; Connect the nexus (hub) to the biomes
    ;; Forest uses a custom named connection: "Puzzling Forest" with synonym "pf"
    (area-connect-rooms! area nexus forest
                         :to '("Puzzling Forest" "pf") :from "nexus")
    (area-connect-west-east! area swamp nexus)
    (area-connect-north-south! area nexus volcano)
    (area-set-entrance! area nexus)
    area))

;; ─── Default world ───────────────────────────────────────────────────────────

(defun new-default-world ()
  "Create the default Apeiron world with all areas (hub, mall, cavern,
eridu), registered via WORLD-ADD-AREA! and linked to one another.  The
nexus acts as a hub to the other areas/universes: each has a named portal
direction from the nexus (e.g. 'Poké Land' leads to the shopping mall,
'Eridu' leads to the first city of Sumer).  Each area's entrance is used
for the cross-area links and the world's starting room."
  (let ((world (make-instance 'mud-world)))
    (let ((hub (build-apeiron-hub))
          (mall (build-shopping-mall))
          (cavern (build-team-rocket-cavern))
          (eridu (build-eridu)))
      (world-add-area! world hub)
      (world-add-area! world mall)
      (world-add-area! world cavern)
      (world-add-area! world eridu)
      ;; Cross-area links — the nexus is a hub to other areas/universes
      ;; Nexus → shopping mall, portal named "Poké Land" (pl)
      (connect-rooms! world (area-entrance hub) (area-entrance mall)
                      :to '("Poké Land" "pl") :from "nexus")
      ;; Nexus → Eridu, portal named "Eridu" (ed)
      (connect-rooms! world (area-entrance hub) (area-entrance eridu)
                      :to '("Eridu" "ed") :from "nexus")
      ;; Mall arcade → Team Rocket cavern maze
      (connect-rooms! world (area-find-room mall "Arcade Zone") (area-entrance cavern)
                      :to "maintenance" :from "mall")
      ;; Players start at the hub's entrance
      (world-set-starting-room! world (area-entrance hub)))
    world))
