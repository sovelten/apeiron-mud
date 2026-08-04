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
  "Connecting rooms creates a connection, a graph edge, and links both
  rooms' ROOM-CONNECTIONS lists so movement code keeps working."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (declare (ignore cave peak))
    (is (= 4 (apeiron.core:area-room-count area)))
    (is (= 3 (apeiron.core:area-connection-count area)))
    (is (= 1 (length (apeiron.core:area-room-connections area tavern))))
    (is (= 2 (length (apeiron.core:area-room-connections area forest))))
    (is (equal (list forest)
               (apeiron.core:area-adjacent-rooms area tavern)))
    ;; Legacy room lookup still works through the linked lists
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
      ;; Idempotent re-registration does not duplicate
      (apeiron.core:area-register-connection! area conn)
      (is (= 1 (apeiron.core:area-connection-count area)))
      (is (= 1 (length (apeiron.core:room-connections tavern)))))))

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
  "Removing a connection drops the edge and cleans the linked lists."
  (multiple-value-bind (area tavern forest cave peak)
      (test-area-chain)
    (declare (ignore cave peak))
    (let ((conn (first (apeiron.core:area-room-connections area tavern))))
      (apeiron.core:area-remove-connection! area conn)
      (is (= 2 (apeiron.core:area-connection-count area)))
      (is (null (apeiron.core:area-room-connections area tavern)))
      (is (null (apeiron.core:room-connections tavern)))
      (is (null (member conn (apeiron.core:room-connections forest)))))))

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
