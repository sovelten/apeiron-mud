(in-package #:apeiron-test)

(in-suite core-suite)

;; ─── Helpers ────────────────────────────────────────────────────────────────

(defun test-area-chain ()
  "Build an area with a linear room chain: tavern - forest - cave - peak.
Returns (values area tavern forest cave peak)."
  (let ((area (apeiron.core:new-area :name "Test Zone")))
    (let ((tavern (apeiron.core:new-room :name "Test Tavern"))
          (forest (apeiron.core:new-room :name "Dark Forest"))
          (cave   (apeiron.core:new-room :name "Echo Cave"))
          (peak   (apeiron.core:new-room :name "Lonely Peak")))
      (apeiron.core:area-connect-rooms! area tavern forest :to "north" :from "south")
      (apeiron.core:area-connect-rooms! area forest cave :to "north" :from "south")
      (apeiron.core:area-connect-rooms! area cave peak :to "north" :from "south")
      (values area tavern forest cave peak))))

;; ─── Basic construction ─────────────────────────────────────────────────────

(test new-area
  "Creating a fresh area gives an empty mud-area with a name."
  (let ((area (apeiron.core:new-area :name "Hub")))
    (is (typep area 'apeiron.core:mud-area))
    (is (equal "Hub" (apeiron.core:object-name area)))
    (is (zerop (apeiron.core:area-room-count area)))
    (is (zerop (apeiron.core:area-connection-count area)))
    (is (null (apeiron.core:area-room-list area)))))

(test area-add-room!
  "Adding rooms registers them as graph vertices and in the ID index."
  (let ((area (apeiron.core:new-area :name "Hub"))
        (tavern (apeiron.core:new-room :name "Tavern"))
        (forest (apeiron.core:new-room :name "Forest")))
    (apeiron.core:area-add-room! area tavern)
    (apeiron.core:area-add-room! area forest)
    (is (= 2 (apeiron.core:area-room-count area)))
    (is (apeiron.core:area-room-p area tavern))
    (is (apeiron.core:area-room-p area forest))
    (is (= 2 (length (apeiron.core:area-room-list area))))
    (is (eq tavern (apeiron.core:area-find-room area "Tavern")))
    (is (eq tavern (apeiron.core:area-find-room area "tavern")))
    (is (null (apeiron.core:area-find-room area "Nowhere")))
    ;; Idempotent
    (apeiron.core:area-add-room! area tavern)
    (is (= 2 (apeiron.core:area-room-count area)))))

(test area-find-room-by-id
  "Finding a room by world-level ID uses the area rooms index."
  (let* ((world (apeiron.core:new-world))
         (area (apeiron.core:new-area :name "Hub"))
         (tavern (apeiron.core:new-room :name "Tavern"))
         (forest (apeiron.core:new-room :name "Forest")))
    (apeiron.core:world-add-object! world tavern)
    (apeiron.core:world-add-object! world forest)
    (apeiron.core:area-add-room! area tavern)
    (apeiron.core:area-add-room! area forest)
    (is (eq tavern (apeiron.core:area-find-room area (apeiron.core:object-id tavern))))
    (is (eq forest (apeiron.core:area-find-room area (apeiron.core:object-id forest))))
    (is (null (apeiron.core:area-find-room area 999)))))

(test area-connect-rooms!
  "Connecting rooms creates a connection, a graph edge, and sets the
  rooms' ROOM-AREA back-reference; movement code finds the exit through
  the area."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (declare (ignore cave peak))
    (is (= 4 (apeiron.core:area-room-count area)))
    (is (= 3 (apeiron.core:area-connection-count area)))
    (is (= 1 (length (apeiron.core:area-room-connections area tavern))))
    (is (= 2 (length (apeiron.core:area-room-connections area forest))))
    (is (equal (list forest)
               (apeiron.core:area-adjacent-rooms area tavern)))
    ;; rooms point back at their area
    (is (eq area (apeiron.core:room-area tavern)))
    (is (eq area (apeiron.core:room-area forest)))
    ;; area connections are found through room-exit-connections
    (is (= 1 (length (apeiron.core:room-exit-connections tavern))))
    (is (eq forest (apeiron.core:room-exit-target tavern "north")))
    (is (eq tavern (apeiron.core:room-exit-target forest "south")))
    (is (null (apeiron.core:room-exit-target tavern "east")))))

(test area-connect-rooms!-requires-directions
  "Both :to and :from must be provided."
  (let ((area (apeiron.core:new-area :name "Hub"))
        (a (apeiron.core:new-room :name "A"))
        (b (apeiron.core:new-room :name "B")))
    (signals error
      (apeiron.core:area-connect-rooms! area a b :to "north"))))

(test area-register-connection!
  "An existing connection (e.g. created by world connect-rooms!) can be
  registered into an area."
  (let* ((world (apeiron.core:new-world))
         (area (apeiron.core:new-area :name "Indexed Zone"))
         (tavern (apeiron.core:new-room :name "Tavern"))
         (forest (apeiron.core:new-room :name "Forest")))
    (apeiron.core:world-add-object! world tavern)
    (apeiron.core:world-add-object! world forest)
    (let ((conn (apeiron.core:connect-rooms! world tavern forest
                                             :to "north" :from "south")))
      (apeiron.core:area-register-connection! area conn)
      (is (= 2 (apeiron.core:area-room-count area)))
      (is (= 1 (apeiron.core:area-connection-count area)))
      (is (equal (list forest) (apeiron.core:area-adjacent-rooms area tavern)))
      (is (eq conn (first (apeiron.core:area-room-connections area tavern))))
      ;; the connection stays in the room's own list (created by
      ;; connect-rooms!) but room-exit-connections dedupes area + own
      (is (= 1 (length (apeiron.core:room-exit-connections tavern))))
      ;; Idempotent re-registration does not duplicate
      (apeiron.core:area-register-connection! area conn)
      (is (= 1 (apeiron.core:area-connection-count area)))
      (is (= 1 (length (apeiron.core:room-exit-connections tavern)))))))

(test new-area-with-rooms-and-connections
  "new-area can pre-populate from room and connection lists."
  (let* ((world (apeiron.core:new-world))
         (tavern (apeiron.core:new-room :name "Tavern"))
         (forest (apeiron.core:new-room :name "Forest")))
    (apeiron.core:world-add-object! world tavern)
    (apeiron.core:world-add-object! world forest)
    (let ((conn (apeiron.core:make-connection tavern "north" forest "south")))
      (let ((area (apeiron.core:new-area
                   :name "Prebuilt"
                   :rooms (list tavern forest)
                   :connections (list conn))))
        (is (= 2 (apeiron.core:area-room-count area)))
        (is (= 1 (apeiron.core:area-connection-count area)))))))

(test area-remove-connection!
  "Removing a connection drops the edge and the area's reference to it."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (declare (ignore cave peak))
    (let ((conn (first (apeiron.core:area-room-connections area tavern))))
      (apeiron.core:area-remove-connection! area conn)
      (is (= 2 (apeiron.core:area-connection-count area)))
      (is (null (apeiron.core:area-room-connections area tavern)))
      ;; the exit is gone from the area-aware lookup too
      (is (null (member conn (apeiron.core:room-exit-connections tavern))))
      (is (null (member conn (apeiron.core:room-exit-connections forest)))))))

(test area-remove-room!
  "Removing a room also removes its incident connections."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (apeiron.core:area-remove-room! area cave)
    (is (= 3 (apeiron.core:area-room-count area)))
    (is (= 1 (apeiron.core:area-connection-count area)))
    (is (not (apeiron.core:area-room-p area cave)))
    (is (null (member cave (apeiron.core:area-adjacent-rooms area forest))))
    ;; forest now only connects to tavern
    (is (equal (list tavern) (apeiron.core:area-adjacent-rooms area forest)))
    (is (null (apeiron.core:room-exit-target forest "north")))))

;; ─── Graph algorithms ───────────────────────────────────────────────────────

(test area-shortest-path
  "Shortest path follows the fewest connections."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (is (equal (list tavern forest cave)
               (apeiron.core:area-shortest-path area tavern cave)))
    (is (equal (list tavern forest cave peak)
               (apeiron.core:area-shortest-path area tavern peak)))
    (is (equal (list cave forest tavern)
               (apeiron.core:area-shortest-path area cave tavern)))
    ;; trivial path for same room
    (is (equal (list forest)
               (apeiron.core:area-shortest-path area forest forest)))))

(test area-shortest-path-unreachable
  "Unreachable rooms yield NIL."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (declare (ignore forest cave peak))
    (let ((void (apeiron.core:new-room :name "Void")))
      (apeiron.core:area-add-room! area void)
      (is (null (apeiron.core:area-shortest-path area tavern void)))
      (is (null (apeiron.core:area-shortest-path area void tavern))))))

(test area-shortest-path-takes-shortcut
  "A direct connection is preferred over a longer route."
  (let ((area (apeiron.core:new-area :name "Shortcut Zone"))
        (start (apeiron.core:new-room :name "Start"))
        (mid   (apeiron.core:new-room :name "Middle"))
        (end   (apeiron.core:new-room :name "End")))
    (apeiron.core:area-connect-rooms! area start mid :to "east" :from "west")
    (apeiron.core:area-connect-rooms! area mid end :to "east" :from "west")
    (apeiron.core:area-connect-rooms! area start end :to "portal" :from "portal")
    (is (equal (list start end)
               (apeiron.core:area-shortest-path area start end)))))

(test area-route
  "Route returns the connections along the shortest path."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (let ((route (apeiron.core:area-route area tavern peak)))
      (is (= 3 (length route)))
      (is (every (lambda (c) (typep c 'apeiron.core:mud-connection)) route))
      ;; each connection links consecutive rooms along the path
      (loop for (from to) on (apeiron.core:area-shortest-path area tavern peak)
            while to
            for conn = (pop route)
            do (is (eq from (apeiron.core:connection-other-room conn to)))))
    ;; unreachable -> nil
    (let ((void (apeiron.core:new-room :name "Void")))
      (apeiron.core:area-add-room! area void)
      (is (null (apeiron.core:area-route area tavern void))))))

(test area-reachable
  "Reachability queries respect the connection graph."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (let ((void (apeiron.core:new-room :name "Void")))
      (apeiron.core:area-add-room! area void)
      (is (apeiron.core:area-reachable-p area tavern peak))
      (is (not (apeiron.core:area-reachable-p area tavern void)))
      (is (= 4 (length (apeiron.core:area-reachable-rooms area tavern))))
      (is (member tavern (apeiron.core:area-reachable-rooms area tavern)))
      ;; isolated room reaches only itself
      (is (equal (list void) (apeiron.core:area-reachable-rooms area void))))))

(test area-connected-components
  "Connected component counting works for one and multiple components."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (is (= 1 (apeiron.core:area-connected-components area)))
    (is (apeiron.core:area-connected-graph-p area))
    (let ((void (apeiron.core:new-room :name "Void")))
      (apeiron.core:area-add-room! area void)
      (is (= 2 (apeiron.core:area-connected-components area)))
      (is (not (apeiron.core:area-connected-graph-p area)))))
  ;; empty area has zero components and is not connected
  (let ((area (apeiron.core:new-area :name "Empty")))
    (is (zerop (apeiron.core:area-connected-components area)))
    (is (not (apeiron.core:area-connected-graph-p area)))))

;; ─── One-way connections ────────────────────────────────────────────────────

(test make-connection-one-way
  "One-way connections record their direction and usability."
  (let ((a (apeiron.core:new-room :name "A"))
        (b (apeiron.core:new-room :name "B")))
    ;; default is bidirectional
    (let ((conn (apeiron.core:make-connection a "north" b "south")))
      (is (eq :both (apeiron.core:connection-one-way conn)))
      (is (not (apeiron.core:connection-one-way-p conn)))
      (is (apeiron.core:connection-usable-p conn a))
      (is (apeiron.core:connection-usable-p conn b)))
    ;; :a-to-b is usable only from ROOM-A
    (let ((conn (apeiron.core:make-connection a "north" b "south"
                                              :one-way :a-to-b
                                              :one-way-message "You can't go back.")))
      (is (eq :a-to-b (apeiron.core:connection-one-way conn)))
      (is (apeiron.core:connection-one-way-p conn))
      (is (apeiron.core:connection-usable-p conn a))
      (is (not (apeiron.core:connection-usable-p conn b)))
      (is (equal "You can't go back."
                 (apeiron.core:connection-one-way-message conn))))
    ;; :b-to-a is usable only from ROOM-B
    (let ((conn (apeiron.core:make-connection a "north" b "south"
                                              :one-way :b-to-a)))
      (is (not (apeiron.core:connection-usable-p conn a)))
      (is (apeiron.core:connection-usable-p conn b)))
    ;; invalid keyword is rejected
    (signals error
      (apeiron.core:make-connection a "north" b "south" :one-way :sideways))))

(test one-way-room-exits
  "Movement code only exposes and allows one-way passages from their
  passable end."
  (let ((area (apeiron.core:new-area :name "Slope"))
        (top (apeiron.core:new-room :name "Cliff Top"))
        (bottom (apeiron.core:new-room :name "Beach")))
    (apeiron.core:area-connect-rooms! area top bottom
                                      :to "down" :from "up"
                                      :one-way :a-to-b
                                      :one-way-message
                                      "The slope is too steep to climb back up.")
    ;; From the top (ROOM-A): the exit is visible and usable.
    (is (equal (list "down")
               (mapcar #'first (apeiron.core:room-exit-list top))))
    (is (eq bottom (apeiron.core:room-exit-target top "down")))
    (is (null (apeiron.core:room-exit-blocked-p top nil "down")))
    ;; From the bottom (ROOM-B): no exit back up, with a flavor message.
    (is (null (apeiron.core:room-exit-list bottom)))
    (is (null (apeiron.core:room-exit-target bottom "up")))
    (is (equal "The slope is too steep to climb back up."
               (apeiron.core:room-exit-blocked-p bottom nil "up")))))

(test one-way-generic-block-message
  "Without a custom message a generic one-way message is shown."
  (let ((area (apeiron.core:new-area :name "Secret"))
        (a (apeiron.core:new-room :name "A"))
        (b (apeiron.core:new-room :name "B")))
    (apeiron.core:area-connect-rooms! area a b
                                      :to "north" :from "south"
                                      :one-way :a-to-b)
    (is (equal "You can't go south from here."
               (apeiron.core:room-exit-blocked-p b nil "south")))))

(test connect-rooms!-one-way
  "World-level connect-rooms! accepts and forwards :one-way."
  (let* ((world (apeiron.core:new-world))
         (a (apeiron.core:new-room :name "A"))
         (b (apeiron.core:new-room :name "B")))
    (apeiron.core:world-add-object! world a)
    (apeiron.core:world-add-object! world b)
    (let ((conn (apeiron.core:connect-rooms! world a b
                                             :to "north" :from "south"
                                             :one-way :a-to-b
                                             :one-way-message
                                             "The passage seals behind you.")))
      (is (apeiron.core:connection-one-way-p conn))
      (is (eq :a-to-b (apeiron.core:connection-one-way conn)))
      (is (equal "The passage seals behind you."
                 (apeiron.core:connection-one-way-message conn)))
      (is (apeiron.core:connection-usable-p conn a))
      (is (not (apeiron.core:connection-usable-p conn b))))))

(test one-way-area-pathfinding
  "Shortest path cannot cross a one-way passage in the wrong direction."
  (let ((area (apeiron.core:new-area :name "Slope Zone"))
        (top (apeiron.core:new-room :name "Top"))
        (mid (apeiron.core:new-room :name "Middle"))
        (bottom (apeiron.core:new-room :name "Bottom")))
    ;; top -> mid is one-way down; mid <-> bottom is bidirectional
    (apeiron.core:area-connect-rooms! area top mid
                                      :to "down" :from "up"
                                      :one-way :a-to-b)
    (apeiron.core:area-connect-rooms! area mid bottom
                                      :to "down" :from "up")
    (is (equal (list top mid bottom)
               (apeiron.core:area-shortest-path area top bottom)))
    (is (equal (list bottom mid)
               (apeiron.core:area-shortest-path area bottom mid)))
    ;; cannot return through the one-way passage
    (is (null (apeiron.core:area-shortest-path area bottom top)))
    (is (null (apeiron.core:area-route area bottom top)))))

(test one-way-area-reachability
  "Reachability respects one-way passages."
  (let ((area (apeiron.core:new-area :name "Slope Zone"))
        (top (apeiron.core:new-room :name "Top"))
        (mid (apeiron.core:new-room :name "Middle"))
        (bottom (apeiron.core:new-room :name "Bottom")))
    (apeiron.core:area-connect-rooms! area top mid
                                      :to "down" :from "up"
                                      :one-way :a-to-b)
    (apeiron.core:area-connect-rooms! area mid bottom
                                      :to "down" :from "up")
    ;; down the slope: everything reachable (sorted by name)
    (is (equal (list bottom mid top)
               (sort (apeiron.core:area-reachable-rooms area top)
                     #'string< :key #'apeiron.core:object-name)))
    ;; up from the bottom: the one-way edge stops you (sorted by name)
    (is (equal (list bottom mid)
               (sort (apeiron.core:area-reachable-rooms area bottom)
                     #'string< :key #'apeiron.core:object-name)))
    (is (apeiron.core:area-reachable-p area top bottom))
    (is (not (apeiron.core:area-reachable-p area bottom top)))))

;; ─── World areas ────────────────────────────────────────────────────────────

(test world-add-area!
  "world-add-area! registers the area plus its rooms and connections,
  and the world-level area queries work."
  (let ((world (apeiron.core:new-world))
        (area (apeiron.core:new-area :name "Cavern")))
    (let ((entrance (apeiron.core:new-room :name "Entrance"))
          (treasure (apeiron.core:new-room :name "Treasure")))
      (apeiron.core:area-connect-rooms! area entrance treasure
                                        :to "east" :from "west")
      (apeiron.core:world-add-area! world area)
      (is (= 1 (apeiron.core:world-total-areas world)))
      (is (eq area (apeiron.core:world-area-by-id world
                                                  (apeiron.core:object-id area))))
      (is (eq area (apeiron.core:world-area-with-name world "cavern")))
      (is (eq area (apeiron.core:world-area-of-room world entrance)))
      (is (eq area (apeiron.core:world-area-of-room world treasure)))
      ;; rooms and the connection are registered in the world too
      (is (= 2 (apeiron.core:world-total-rooms world)))
      (is (eq entrance (apeiron.core:world-room-by-id world
                                                      (apeiron.core:object-id entrance))))
      (is (member area (apeiron.core:world-all-areas world)))
      ;; idempotent — re-adding does not duplicate anything
      (apeiron.core:world-add-area! world area)
      (is (= 1 (apeiron.core:world-total-areas world)))
      (is (= 2 (apeiron.core:world-total-rooms world)))
      ;; the area connection is found through the area, not duplicated
      ;; into the room's own connections list
      (is (zerop (length (apeiron.core:room-connections entrance))))
      (is (= 1 (length (apeiron.core:room-exit-connections entrance)))))))

(test world-remove-area!
  "Removing an area unindexes it but keeps its rooms."
  (let ((world (apeiron.core:new-world))
        (area (apeiron.core:new-area :name "Cavern")))
    (let ((entrance (apeiron.core:new-room :name "Entrance")))
      (apeiron.core:area-add-room! area entrance)
      (apeiron.core:world-add-area! world area)
      (is (= 1 (apeiron.core:world-total-areas world)))
      (is (= 1 (apeiron.core:world-total-rooms world)))
      (apeiron.core:world-remove-area! world area)
      (is (zerop (apeiron.core:world-total-areas world)))
      (is (= 1 (apeiron.core:world-total-rooms world))
          "Rooms should survive area removal"))))

(test area-rebuild-graph!
  "area-rebuild-graph! reconstructs the graph from the stored slots."
  (let ((area (apeiron.core:new-area :name "Rebuild"))
        (a (apeiron.core:new-room :name "A"))
        (b (apeiron.core:new-room :name "B"))
        (c (apeiron.core:new-room :name "C")))
    (apeiron.core:area-connect-rooms! area a b :to "north" :from "south")
    (apeiron.core:area-connect-rooms! area b c :to "east" :from "west")
    (is (= 3 (apeiron.core:area-room-count area)))
    (is (= 2 (apeiron.core:area-connection-count area)))
    ;; nuke the graph as a persistent restore would (unbound transient slot)
    (slot-makunbound area 'apeiron.core::graph)
    (apeiron.core:area-rebuild-graph! area)
    (is (= 3 (apeiron.core:area-room-count area)))
    (is (= 2 (apeiron.core:area-connection-count area)))
    (is (equal (list a b c)
               (apeiron.core:area-shortest-path area a c)))))

(test cardinal-connection-helpers
  "The standard cardinal helpers add the conventional single-letter
  synonyms (n/s/e/w) and connect rooms in the right directions."
  (let ((area (apeiron.core:new-area :name "Cardinals"))
        (north (apeiron.core:new-room :name "North"))
        (south (apeiron.core:new-room :name "South"))
        (west (apeiron.core:new-room :name "West"))
        (east (apeiron.core:new-room :name "East")))
    (apeiron.core:area-connect-north-south! area north south)
    (apeiron.core:area-connect-west-east! area west east)
    ;; primary directions work
    (is (eq south (apeiron.core:room-exit-target north "south")))
    (is (eq north (apeiron.core:room-exit-target south "north")))
    (is (eq east (apeiron.core:room-exit-target west "east")))
    (is (eq west (apeiron.core:room-exit-target east "west")))
    ;; single-letter synonyms work too
    (is (eq south (apeiron.core:room-exit-target north "s")))
    (is (eq north (apeiron.core:room-exit-target south "n")))
    (is (eq east (apeiron.core:room-exit-target west "e")))
    (is (eq west (apeiron.core:room-exit-target east "w")))
    ;; exits list shows the cardinal directions compactly
    (is (equal (list "south")
               (mapcar #'first (apeiron.core:room-exit-list north))))
    (is (equal (list "east")
               (mapcar #'first (apeiron.core:room-exit-list west)))))
  ;; cardinal-spec validates its input
  (is (equal '("north" "n") (apeiron.core:cardinal-spec "north")))
  (is (equal '("south" "s") (apeiron.core:cardinal-spec "SOUTH")))
  (signals error (apeiron.core:cardinal-spec "sideways")))

(test one-area-per-room-invariant
  "A room cannot belong to more than one area in a world."
  (let ((world (apeiron.core:new-world))
        (area-a (apeiron.core:new-area :name "Area A"))
        (area-b (apeiron.core:new-area :name "Area B"))
        (room (apeiron.core:new-room :name "Shared Room")))
    (apeiron.core:area-add-room! area-a room)
    (apeiron.core:world-add-area! world area-a)
    (is (eq area-a (apeiron.core:world-area-of-room world room)))
    ;; Adding a second area that claims the same room is rejected
    (apeiron.core:area-add-room! area-b room)
    (signals error (apeiron.core:world-add-area! world area-b))
    ;; nothing was registered
    (is (= 1 (apeiron.core:world-total-areas world)))
    (is (eq area-a (apeiron.core:world-area-of-room world room)))))

(test area-entrance
  "An area can have an optional entrance room."
  ;; default: no entrance
  (let ((area (apeiron.core:new-area :name "No Entrance")))
    (is (null (apeiron.core:area-entrance area))))
  ;; set/read via area-set-entrance!
  (let ((area (apeiron.core:new-area :name "With Entrance"))
        (room (apeiron.core:new-room :name "Front Door")))
    (apeiron.core:area-add-room! area room)
    (is (eq room (apeiron.core:area-set-entrance! area room)))
    (is (eq room (apeiron.core:area-entrance area)))
    ;; clear it
    (apeiron.core:area-set-entrance! area nil)
    (is (null (apeiron.core:area-entrance area))))
  ;; :entrance initarg via new-area
  (let* ((room (apeiron.core:new-room :name "Gate"))
         (area (apeiron.core:new-area :name "Init Entrance" :entrance room)))
    (is (eq room (apeiron.core:area-entrance area)))))

(test room-area-back-reference
  "area-add-room! sets the room's ROOM-AREA; area-remove-room! clears it."
  (let ((area (apeiron.core:new-area :name "Zone"))
        (room (apeiron.core:new-room :name "Lobby")))
    (is (null (apeiron.core:room-area room)))
    (apeiron.core:area-add-room! area room)
    (is (eq area (apeiron.core:room-area room)))
    (apeiron.core:area-remove-room! area room)
    (is (null (apeiron.core:room-area room)))))

(test room-exit-connections
  "Exits are the union of area connections (preferred) and the room's own
  connections, with a fallback for rooms outside any area."
  (let ((area (apeiron.core:new-area :name "Zone"))
        (hub (apeiron.core:new-room :name "Hub"))
        (spoke (apeiron.core:new-room :name "Spoke")))
    (apeiron.core:area-connect-rooms! area hub spoke
                                      :to "north" :from "south")
    ;; rooms outside an area fall back to their own connections
    (let ((lonely (apeiron.core:new-room :name "Lonely"))
          (other (apeiron.core:new-room :name "Other")))
      (let ((world (apeiron.core:new-world)))
        (apeiron.core:connect-rooms! world lonely other :to "east" :from "west")
        (is (null (apeiron.core:room-area lonely)))
        (is (= 1 (length (apeiron.core:room-exit-connections lonely))))
        (is (eq other (apeiron.core:room-exit-target lonely "east")))))
    ;; area room: area connection preferred, cross-area added on top
    (let ((world (apeiron.core:new-world)))
      (apeiron.core:world-add-area! world area)
      (let ((outside (apeiron.core:new-room :name "Outside")))
        (apeiron.core:connect-rooms! world hub outside :to "door" :from "portal")
        (is (eq area (apeiron.core:room-area hub)))
        (is (= 2 (length (apeiron.core:room-exit-connections hub))))
        (is (eq spoke (apeiron.core:room-exit-target hub "north")))
        (is (eq outside (apeiron.core:room-exit-target hub "door")))
        ;; room's own list holds only the cross-area connection
        (is (= 1 (length (apeiron.core:room-connections hub))))))))
