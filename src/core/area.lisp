;;;; src/core/area.lisp — Areas: a set of rooms + connections as a graph
;;;;
;;;; An Area is a named collection of rooms and the connections between
;;;; them, backed by a CL-GRAPH undirected graph.  Rooms are vertices and
;;;; MUD-CONNECTIONs are edges, so the full cl-graph toolbox (shortest
;;;; paths, reachability, connected components, ...) is available on top
;;;; of the plain room/connection data.
;;;;
;;;; The graph is the authoritative structure for the room set and the
;;;; connections between them: AREA-ROOM-LIST / AREA-ROOM-COUNT derive
;;;; from the graph's vertices, and AREA-ROOM-CONNECTIONS /
;;;; AREA-ADJACENT-ROOMS from a vertex's incident edges / neighbours.
;;;; The ROOMS slot is a flat list keyed by object identity (so rooms
;;;; can be added before world registration assigns OBJECT-IDs), and
;;;; CONNECTIONS a flat list for callers that want to iterate
;;;; connections directly.
;;;;
;;;; Connections registered through an area are also pushed onto the
;;;; endpoints' ROOM-CONNECTIONS lists (like CONNECT-ROOMS! at the world
;;;; level), so the existing movement / exit code keeps working.
;;;;
;;;; One-way connections (CONNECTION-ONE-WAY set to :A-TO-B or :B-TO-A)
;;;; are respected by the path-finding and reachability functions:
;;;; edges are only crossed from their passable end.  CONNECTED-COMPONENTS
;;;; still counts weakly (ignoring direction), matching the intuitive
;;;; notion of "this area is one place even if some passages are one-way".

(in-package #:apeiron.core)

(defclass mud-area (mud-object)
  ((rooms :initarg :rooms
          :accessor area-rooms
          :initform nil
          :documentation "Rooms in the area, as a list.  A list (rather
than a hash keyed by OBJECT-ID) so that rooms which have not yet been
registered with a world — and therefore share the unset OBJECT-ID -1 —
can still coexist in one area.  The graph is the authoritative room set.")
   (connections :initarg :connections
                :accessor area-connections
                :initform '()
                :documentation "Flat list of MUD-CONNECTION objects in this area.")
   (entrance :initarg :entrance
             :accessor area-entrance
             :initform nil
             :documentation "Optional entrance room of the area (a MUD-ROOM),
or NIL when the area has no designated entrance.")
   (graph :initarg :graph
          :accessor area-graph
          :initform (make-instance 'cl-graph:graph-container
                                   :default-edge-type :undirected)
          :documentation "CL-GRAPH undirected graph whose vertices are MUD-ROOMs
and whose edges carry the MUD-CONNECTION as their element."))
  (:documentation "A named area: a set of rooms and the connections between
them, backed by a CL-GRAPH graph so complex operations such as path finding
and reachability queries can run on top of the plain room/connection data."))

(defmethod print-object ((area mud-area) stream)
  (print-unreadable-object (area stream :type t)
    (format stream "~A (~D rooms, ~D connections)~@[ — entrance: ~A~]"
            (object-name area)
            (area-room-count area)
            (area-connection-count area)
            (and (area-entrance area) (object-name (area-entrance area))))))

;; ─── Construction ──────────────────────────────────────────────────────────

(defun area-rooms-normalized (area)
  "Return AREA's rooms as a list, migrating an old-format hash-table in
place if one was restored from a pre-refactor snapshot.

Before the list refactor, AREA-ROOMS was a hash-table keyed by OBJECT-ID.
Persistent snapshots taken under that layout restore the slot as a
hash-table; the new list-based code would choke on it.  This converts
the stored value once, then returns the list."
  (let ((rooms (area-rooms area)))
    (when (hash-table-p rooms)
      (setf (area-rooms area)
            (loop for v being the hash-values of rooms collect v)))
    (area-rooms area)))

(defun area-add-room! (area room)
  "Add ROOM to AREA (idempotent per object identity).  Registers the room
as a vertex of the area's graph and in the rooms list, and sets the room's
ROOM-AREA back-reference to AREA.  Returns ROOM."
  ;; Normalize any legacy hash-table first, then push onto the list.
  (let ((rooms (area-rooms-normalized area)))
    (pushnew room rooms :test #'eq)
    (setf (area-rooms area) rooms))
  (setf (room-area room) area)
  (cl-graph:add-vertex (area-graph area) room)
  room)

(defun area-remove-room! (area room)
  "Remove ROOM from AREA along with every connection incident to it.
The room and its connections are removed from the graph, the rooms list
and the connections list; the endpoints' ROOM-CONNECTIONS lists are also
cleaned up, and the room's ROOM-AREA back-reference is cleared.
Returns ROOM."
  (setf (area-rooms area)
        (remove room (area-rooms-normalized area) :test #'eq))
  ;; Drop incident connections from the flat list and the other rooms.
  (dolist (conn (area-room-connections area room))
    (area-remove-connection! area conn))
  ;; Remove the vertex (and any remaining incident edges) from the graph.
  (let ((vertex (cl-graph:find-vertex (area-graph area) room nil)))
    (when vertex
      (cl-graph:delete-vertex (area-graph area) vertex)))
  (setf (room-area room) nil)
  room)

(defun area-register-connection! (area connection)
  "Register an existing MUD-CONNECTION in AREA.

Both endpoint rooms are added to the area (as vertices, setting their
ROOM-AREA back-reference), an undirected edge carrying CONNECTION is
added to the graph, and the connection is pushed onto AREA-CONNECTIONS.
The connection is deliberately NOT pushed onto the rooms' CONNECTIONS
lists: area connections live in the area and are found through
ROOM-EXIT-CONNECTIONS.  Idempotent per room pair: an area holds at most
one connection between two rooms.

Returns CONNECTION."
  (let ((room-a (connection-room-a connection))
        (room-b (connection-room-b connection)))
    (area-add-room! area room-a)
    (area-add-room! area room-b)
    (cl-graph:add-edge-between-vertexes
     (area-graph area) room-a room-b
     :edge-type :undirected
     :value connection
     :if-duplicate-do :ignore)
    (pushnew connection (area-connections area))
    connection))

(defun area-connect-rooms! (area room-a room-b
                           &key to from name blocked blocked-message
                             one-way one-way-message)
  "Create a bidirectional Connection between ROOM-A and ROOM-B inside AREA.

TO is the direction from ROOM-A to ROOM-B (e.g. \"north\"); FROM is the
direction from ROOM-B to ROOM-A (e.g. \"south\").  Each accepts a string
or a list of strings with synonyms (e.g. '(\"north\" \"n\")).  Neither may
be NIL.  BLOCKED / BLOCKED-MESSAGE behave like CONNECT-ROOMS!.

ONE-WAY restricts the passage to a single direction (:A-TO-B or :B-TO-A,
default :BOTH); ONE-WAY-MESSAGE is the message shown when a character tries
to traverse it the wrong way.

Creates the MUD-CONNECTION, registers it in the area graph and returns it."
  (when (or (null to) (null from))
    (error "area-connect-rooms!: :to and :from are required and cannot be nil."))
  (area-register-connection!
   area
   (make-connection room-a to room-b from
                    :name name :blocked blocked
                    :blocked-message blocked-message
                    :one-way one-way
                    :one-way-message one-way-message)))

(defun area-connect-north-south! (area north-room south-room &rest args)
  "Connect NORTH-ROOM (left arg) south to SOUTH-ROOM (right arg) inside AREA.
From SOUTH-ROOM you go north to NORTH-ROOM.
Standard cardinal synonyms are added: \"s\" from north-room, \"n\" from
south-room."
  (apply #'area-connect-rooms! area north-room south-room
         :to (cardinal-spec "south") :from (cardinal-spec "north")
         args))

(defun area-connect-west-east! (area west-room east-room &rest args)
  "Connect WEST-ROOM (left arg) east to EAST-ROOM (right arg) inside AREA.
From EAST-ROOM you go west to WEST-ROOM.
Standard cardinal synonyms are added: \"e\" from west-room, \"w\" from
east-room."
  (apply #'area-connect-rooms! area west-room east-room
         :to (cardinal-spec "east") :from (cardinal-spec "west")
         args))

(defun area-remove-connection! (area connection)
  "Remove CONNECTION from AREA: drop its graph edge and remove it from
AREA-CONNECTIONS.  The endpoints' ROOM-CONNECTIONS lists are also cleaned
up as a legacy safeguard (older worlds stored area connections there).
Returns CONNECTION."
  (let ((room-a (connection-room-a connection))
        (room-b (connection-room-b connection)))
    (cl-graph:delete-edge-between-vertexes (area-graph area) room-a room-b)
    (setf (area-connections area)
          (remove connection (area-connections area)))
    (setf (room-connections room-a)
          (remove connection (room-connections room-a)))
    (setf (room-connections room-b)
          (remove connection (room-connections room-b))))
  connection)

(defun area-rebuild-graph! (area)
  "Rebuild the area's cl-graph index from its ROOMS and CONNECTIONS slots.

The graph is a derived index; this resets it to a fresh graph-container
and re-adds every room as a vertex and every connection as an edge.  It
is called automatically after a persistent restore (the graph is a
transient slot and is not stored) and is useful after directly editing
the room/connection lists.  Each room's ROOM-AREA back-reference is also
restored, so areas restored from older snapshots (whose rooms predate the
back-reference) still find their connections.  Returns AREA."
  (setf (area-graph area)
        (make-instance 'cl-graph:graph-container :default-edge-type :undirected))
  (dolist (room (area-rooms-normalized area))
    (setf (room-area room) area)
    (cl-graph:add-vertex (area-graph area) room))
  (dolist (conn (area-connections area))
    (cl-graph:add-edge-between-vertexes
     (area-graph area) (connection-room-a conn) (connection-room-b conn)
     :edge-type :undirected
     :value conn
     :if-duplicate-do :ignore))
  ;; The graph is the authoritative room set.  The ROOMS list may be
  ;; incomplete in restored snapshots (the pre-refactor hash collapsed
  ;; rooms sharing OBJECT-ID -1 into one entry), so re-sync it from the
  ;; rebuilt graph to keep AREA-ROOMS and the graph consistent.
  (setf (area-rooms area) (area-room-list area))
  area)

(defun area-set-entrance! (area room)
  "Set ROOM as the entrance of AREA, or clear it with NIL.

ROOM should be one of the area's rooms (or NIL).  Returns ROOM."
  (setf (area-entrance area) room))

(defun new-area (&key name (rooms nil) (connections nil) (entrance nil))
  "Create a new empty area, optionally pre-populated with ROOMS (a list of
MUD-ROOMs), CONNECTIONS (a list of MUD-CONNECTIONs, whose endpoint
rooms are added automatically), and an optional ENTRANCE room.  Returns
the MUD-AREA."
  (let ((area (make-instance 'mud-area :name name :entrance entrance)))
    (dolist (room rooms)
      (area-add-room! area room))
    (dolist (connection connections)
      (area-register-connection! area connection))
    area))

;; ─── Queries ───────────────────────────────────────────────────────────────

(defun area-room-p (area room)
  "Return non-NIL if ROOM is part of AREA."
  (not (null (cl-graph:find-vertex (area-graph area) room nil))))

(defun area-find-room (area id-or-name)
  "Find a room in AREA by world-level ID (an integer) or by name
(a string, case-insensitive).  Returns the room or NIL.

Integer lookups scan the rooms list (with legacy hash migration);
name lookups scan the graph-derived room list, which is authoritative
and complete even when a restored snapshot's ROOMS slot was incomplete."
  (etypecase id-or-name
    (integer (find id-or-name (area-rooms-normalized area)
                   :key #'object-id :test #'eql))
    (string  (find id-or-name (area-room-list area)
                   :test (lambda (name room)
                           (string-equal name (object-name room)))))))

(defun area-room-list (area)
  "Return the list of all rooms in AREA (derived from the graph's vertices)."
  (mapcar #'cl-graph:element (cl-graph:vertexes (area-graph area))))

(defun area-room-count (area)
  "Return the number of rooms in AREA."
  (length (cl-graph:vertexes (area-graph area))))

(defun area-connection-count (area)
  "Return the number of connections in AREA."
  (length (area-connections area)))

(defun area-room-connections (area room)
  "Return the list of MUD-CONNECTIONs incident to ROOM in AREA."
  (let ((vertex (cl-graph:find-vertex (area-graph area) room nil)))
    (when vertex
      (mapcar #'cl-graph:element (cl-graph:edges vertex)))))

(defun area-adjacent-rooms (area room)
  "Return the list of rooms directly connected to ROOM in AREA."
  (let ((vertex (cl-graph:find-vertex (area-graph area) room nil)))
    (when vertex
      (mapcar #'cl-graph:element (cl-graph:neighbor-vertexes vertex)))))

;; ─── Graph algorithms ──────────────────────────────────────────────────────

(defun area-bfs-tree (area room)
  "Breadth-first traversal of AREA starting at ROOM, respecting one-way
connections (an edge is only crossed when its connection is usable from
the room you are leaving).

Returns a hash-table mapping each reachable vertex to its parent vertex
(ROOM's vertex maps to :ROOT).  Returns an empty hash-table when ROOM is
not part of the area."
  (let* ((graph (area-graph area))
         (start (cl-graph:find-vertex graph room nil))
         (parents (make-hash-table :test #'eq))
         (queue (list start)))
    (when start
      (setf (gethash start parents) :root)
      (loop while queue
            for current = (pop queue)
            for current-room = (cl-graph:element current)
            do (dolist (edge (cl-graph:edges current))
                 (let* ((neighbor (cl-graph:other-vertex edge current))
                        (conn (cl-graph:element edge)))
                   (when (and (not (gethash neighbor parents))
                              (or (null conn)
                                  (connection-usable-p conn current-room)))
                     (setf (gethash neighbor parents) current)
                     (push neighbor queue))))))
    parents))

(defun area-shortest-path (area room-a room-b)
  "Return the shortest path from ROOM-A to ROOM-B as a list of rooms
(inclusive), or NIL if ROOM-B is unreachable from ROOM-A.

The path is shortest in the number of hops (all edges count equally) and
respects one-way connections: a one-way passage can only be used from its
passable end.  For ROOM-A = ROOM-B the trivial path (ROOM-A) is returned."
  (let* ((graph (area-graph area))
         (start (cl-graph:find-vertex graph room-a nil))
         (target (cl-graph:find-vertex graph room-b nil)))
    (when (and start target)
      (if (eq room-a room-b)
          (list room-a)
          (let ((parents (area-bfs-tree area room-a)))
            (when (gethash target parents)
              (let ((path nil)
                    (v target))
                (loop
                  (push (cl-graph:element v) path)
                  (if (eq v start)
                      (return path)
                      (setf v (gethash v parents)))))))))))

(defun area-route (area room-a room-b)
  "Return the list of MUD-CONNECTIONs traversed by a shortest path from
ROOM-A to ROOM-B, or NIL if ROOM-B is unreachable from ROOM-A."
  (let ((path (area-shortest-path area room-a room-b)))
    (when path
      (loop for (from to) on path
            while to
            for edge = (cl-graph:find-edge-between-vertexes
                        (area-graph area) from to)
            collect (cl-graph:element edge)))))

(defun area-reachable-p (area room-a room-b)
  "Return non-NIL if ROOM-B can be reached from ROOM-A via connections
in AREA."
  (not (null (area-shortest-path area room-a room-b))))

(defun area-reachable-rooms (area room)
  "Return every room reachable from ROOM via connections in AREA
(including ROOM itself), respecting one-way connections: a one-way
passage can only be used from its passable end."
  (let ((parents (area-bfs-tree area room)))
    (mapcar #'cl-graph:element
            (loop for vertex being the hash-keys of parents
                  collect vertex))))

(defun area-connected-components (area)
  "Return the number of connected components in AREA (0 when empty).

Implemented with the graph's transitive closure: repeatedly pick an
unvisited room, remove its whole reachable set, and count."
  (let ((unvisited (copy-list (cl-graph:vertexes (area-graph area))))
        (count 0))
    (loop while unvisited do
      (incf count)
      (let* ((start (pop unvisited))
             (component (cl-graph:get-transitive-closure (list start))))
        (setf unvisited (set-difference unvisited component :test #'eq))))
    count))

(defun area-connected-graph-p (area)
  "Return non-NIL if every room in AREA is reachable from every other
(and the area contains at least one room)."
  (and (plusp (area-room-count area))
       (= 1 (area-connected-components area))))
