(in-package #:apeiron.core)

(named-readtables:in-readtable pythonic-string-syntax)

(defsection @world (:title "World")
  """The *world* is the root object of an Apeiron game. It owns every
  room, area, character and item, assigns world-level IDs, and is the
  object that the persistence layer stores (see `apeiron/persistence`).

  Create a world with NEW-WORLD, add content with WORLD-ADD-OBJECT!
  and connect rooms with CONNECT-ROOMS!. See also @COMMANDS for the
  player-facing command layer. The full API of this package is
  generated automatically in the manual's API reference."""
  (new-world function)
  (world-parser generic-function)
  (world-add-object! function)
  (connect-rooms! generic-function)
  (place-character! function)
  (world-broadcast function)
  (create-object! generic-function)
  (copy-object! generic-function)
  (@commands section))

(defclass mud-world ()
  ((id-counter :initarg :id-counter
               :accessor world-id-counter
               :initform 0
               :documentation "Monotonic ID counter for assigning world-level IDs.")
   (config :initarg :config
           :accessor world-config
           :initform (make-hash-table :test #'eq)
           :documentation "Configuration hash table (keys are keywords).")
   (characters :initarg :characters
            :accessor world-characters
            :initform (make-hash-table :test #'equal)
            :documentation "Stores all online/active characters in world")
   (objects :initarg :objects
            :accessor world-objects
            :initform (make-hash-table :test #'eql)
            :documentation "All objects in the world, keyed by world-level ID.")
   (rooms :initarg :rooms
          :accessor world-rooms
          :initform (make-hash-table :test #'eql)
          :documentation "All rooms in the world, keyed by world-level ID.")
   (areas :initarg :areas
          :accessor world-areas
          :initform (make-hash-table :test #'eql)
          :documentation "All areas in the world, keyed by world-level ID.")
   (parser :initarg :parser
           :accessor world-parser
           :initform (make-instance 'mud-parser)
           :documentation "Command parser used to turn player input into command name and args."))
  (:documentation "Configuration root for the MUD world.  Rooms, guestbooks,
   and other objects are stored as independent BKNR persistent objects."))

(defun get-config-key (world key)
  "Get a configuration value from the world config."
  (gethash key (world-config world)))

(defun new-world () (make-instance 'mud-world))

(defun world-gen-id! (world)
  ;; Increment id counter and return new id
  (incf (world-id-counter world)))

(defun world-add-object! (world object)
  "Assign a world-level ID to an object, register it in the world's
indices, and return the object."
  (when (eq -1 (object-id object)) ;; Only set if unset
    (setf (object-id object) (world-gen-id! world)))
  ;; Register in world's objects hash table
  (setf (gethash (object-id object) (world-objects world)) object)
  ;; Also register in rooms hash table if it's a room
  (when (typep object 'mud-room)
    (setf (gethash (object-id object) (world-rooms world)) object))
  ;; Also register in areas hash table if it's an area
  (when (typep object 'mud-area)
    (setf (gethash (object-id object) (world-areas world)) object))
  ;; Also register in characters hash table if it's a character
  (when (typep object 'mud-character)
    (setf (gethash (object-id object) (world-characters world)) object))
  object)

(defgeneric connect-rooms! (world room-a room-b
                            &key to from name blocked blocked-message
                              one-way one-way-message)
  (:documentation "Create a bidirectional Connection between ROOM-A and ROOM-B in WORLD.

TO is the direction name from ROOM-A to ROOM-B (e.g. \"north\").
FROM is the direction name from ROOM-B to ROOM-A (e.g. \"south\").
Each of TO and FROM accepts either a string (just the direction) or a
list of strings whose first element is the direction and the remaining
elements are synonyms (e.g. '(\"north\" \"n\")).  Neither may be NIL.

When BLOCKED is true the passage starts blocked and cannot be traversed.
BLOCKED-MESSAGE is shown to characters when they try to pass.

ONE-WAY restricts the passage to a single direction:
  :BOTH    (default) passable in either direction
  :A-TO-B  passable only from ROOM-A to ROOM-B
  :B-TO-A  passable only from ROOM-B to ROOM-A
ONE-WAY-MESSAGE is shown when a character tries to traverse the passage
the wrong way (e.g. \"The slope is too steep to climb back up.\").

The connection is linked into both rooms' CONNECTIONS lists and
registered in the world.

Returns the registered MUD-CONNECTION instance."))

(defmethod connect-rooms! ((world mud-world) room-a room-b
                           &key to from
                             (name (format nil "passage between ~A and ~A"
                                           (object-name room-a)
                                           (object-name room-b)))
                             blocked blocked-message
                             one-way one-way-message)
  (when (or (null to) (null from))
    (error "connect-rooms!: :to and :from are required and cannot be nil."))
  (let* ((conn (make-connection room-a to room-b from
                                :name name :blocked blocked
                                :blocked-message blocked-message
                                :one-way one-way
                                :one-way-message one-way-message))
         (registered (create-object! world conn)))
    (push registered (room-connections room-a))
    (push registered (room-connections room-b))
    registered))

(defun connect-north-south! (world north-room south-room &rest args)
  "Connect NORTH-ROOM (left arg) south to SOUTH-ROOM (right arg).
From SOUTH-ROOM you go north to NORTH-ROOM.
Standard cardinal synonyms are added: \"s\" from north-room, \"n\" from
south-room."
  (apply #'connect-rooms! world north-room south-room
         :to (cardinal-spec "south") :from (cardinal-spec "north")
         args))

(defun connect-west-east! (world west-room east-room &rest args)
  "Connect WEST-ROOM (left arg) east to EAST-ROOM (right arg).
From EAST-ROOM you go west to WEST-ROOM.
Standard cardinal synonyms are added: \"e\" from west-room, \"w\" from
east-room."
  (apply #'connect-rooms! world west-room east-room
         :to (cardinal-spec "east") :from (cardinal-spec "west")
         args))

(defun world-set-starting-room! (world room)
  (setf (gethash :starting-room-id (world-config world)) (object-id room)))

(defun starting-room (world)
  "Get the starting room of the world."
  (world-room-by-id world (get-config-key world :starting-room-id)))

(defun place-character! (world character)
  "Place CHARACTER in the world's starting room and return the character.
The character must already be registered in the world (via CREATE-OBJECT!
or WORLD-ADD-OBJECT!).  This only sets location and room membership —
it does not assign IDs or index into world tables."
  (let ((room (starting-room world)))
    (when room
      (setf (object-location character) room)
      (container-add-object room character))
    character))

(defun find-character-by-owner (world account-name)
  "Find a character in the world owned by ACCOUNT-NAME (a string), or NIL."
  (loop for char being the hash-values of (world-characters world)
        when (and (character-owner char)
                  (string-equal (character-owner char) account-name))
        return char))

(defun world-total-characters (world)
  "Count active (online) characters — those with a live session."
  (loop for character being the hash-values of (world-characters world)
        count (character-session character)))

(defgeneric world-remove-object! (world object)
  (:documentation
   "Remove OBJECT from all world indices (world-objects, world-characters,
world-rooms, world-areas).  The default method handles hash-table removal; the
persistence layer specialises this to also destroy the BKNR object.
Returns the removed OBJECT.")
  (:method (world object)
    (remhash (object-id object) (world-objects world))
    (when (typep object 'mud-character)
      (remhash (object-id object) (world-characters world)))
    (when (typep object 'mud-room)
      (remhash (object-id object) (world-rooms world)))
    (when (typep object 'mud-area)
      (setf (area-world object) nil)
      (remhash (object-id object) (world-areas world)))
    (log-message "~A removed from world indices" (object-name object))
    object))

(defun displace-character! (character)
  "Remove CHARACTER from their current room location.
Sets location to NIL and removes from the room's contents.  Does NOT
touch world indices — use WORLD-REMOVE-OBJECT! for that."
  (let ((room (object-location character)))
    (when (typep room 'mud-room)
      (container-remove-object room character))
    (setf (object-location character) nil)))

(defun drop-character-items! (character)
  "Unequip everything CHARACTER is wearing and drop all carried items
into their current room (if any), so the items survive the character's
removal.  Used when removing guest characters."
  (let ((room (object-location character)))
    ;; Unequip worn items back into the inventory
    (dolist (pair (copy-list (character-worn-items character)))
      (unequip character (cdr pair)))
    ;; Drop everything now carried into the room
    (let ((items (copy-list (container-all-objects character))))
      (dolist (item items)
        (container-remove-object character item)
        (when room
          (container-add-object room item))))
    (values)))

(defun world-remove-character! (world character)
  "Remove a character from the world.
Owned characters (with a non-nil OWNER) are displaced from their room
but kept in world indices. Guest characters (no owner) are completely
removed: their worn and carried items are first dropped into the room
(see DROP-CHARACTER-ITEMS!), then the character is removed from the
indices and destroyed."
  (let ((name (object-name character)))
    (if (character-owner character)
        ;; Owned: stay in world indices
        (progn
          (displace-character! character)
          (log-message "~A displaced from world" name))
        ;; Guest: drop items, remove from indices and destroy
        (progn
          (drop-character-items! character)
          (displace-character! character)
          (world-remove-object! world character)
          (log-message "~A removed from world" name)))))

(defun character-by-id (world char-id)
  "Get a character by ID."
  (gethash char-id (world-characters world)))

(defun characters (world)
  "Get all active (online) characters — those with a live session."
  (loop for character being the hash-values of (world-characters world)
        when (character-session character)
        collect character))

(defun world-broadcast (world message &optional exclude-character)
  "Broadcast a message to all characters (optionally excluding one)."
  (dolist (character (characters world))
    (unless (and exclude-character (eq (object-id character) (object-id exclude-character)))
      (character-send-message character message))))

;; ─── World-level object/room queries ─────────────────────────────────────

(defun world-object-by-id (world object-id)
  "Look up an object in the world by its world-level ID."
  (gethash object-id (world-objects world)))

(defun world-object-with-name (world name)
  "Return the first object in the world with the given NAME, or NIL."
  (loop for obj being the hash-values of (world-objects world)
        when (string-equal (object-name obj) name)
        return obj))

(defun world-objects-matching (world name)
  "Return a list of all objects in WORLD whose name or aliases match NAME.
Matching is done via OBJECT-NAME-MATCHES (case-insensitive, whole-word, and alias checks).
Returns an empty list when no objects match."
  (loop for obj being the hash-values of (world-objects world)
        when (object-name-matches obj name)
        collect obj))

(defun world-all-objects (world)
  "Return all objects registered in the world."
  (loop for obj being the hash-values of (world-objects world)
        collect obj))

(defun world-all-rooms (world)
  "Return all objects registered in the world."
  (loop for room being the hash-values of (world-rooms world)
        collect room))

(defun world-room-by-id (world room-id)
  "Look up a room in the world by its world-level ID."
  (gethash room-id (world-rooms world)))

(defun world-total-rooms (world)
  "Return the number of rooms in the world."
  (hash-table-count (world-rooms world)))

(defgeneric world-add-area! (world area)
  (:documentation "Register AREA and everything in it (rooms, contained
objects, and connections) in WORLD.

Each room and connection in the area is registered with the world
(assigning world-level IDs and materializing them for persistent worlds),
as is every non-character object contained in the area's rooms (NPCs,
guestbooks, items).  The area itself is then registered and indexed in
WORLD-AREAS.  The call is idempotent: objects that are already registered
are simply re-indexed.

A room may belong to at most one area: if any room in AREA already belongs
to a different area of WORLD, an error is signaled before anything is
registered.

The generic function is specialized on WORLD so persistent worlds can
materialize the whole closure into the datastore in a single transaction
before indexing it.  Returns AREA."))


(defmethod world-add-area! ((world mud-world) area)
  "Transient worlds: assign world-level IDs and index everything, with no
persistence concerns.  See WORLD-ADD-AREA!."
  ;; Enforce the one-area-per-room invariant before mutating anything.
  (dolist (room (area-room-list area))
    (let ((owner (world-area-of-room world room)))
      (when (and owner (not (eq owner area)))
        (error "world-add-area!: room ~A already belongs to area ~A; a room can only belong to one area."
               (object-name room) (object-name owner)))))
  ;; Rooms, then everything inside them, then connections, then the area.
  (dolist (room (area-room-list area))
    (create-object! world room))
  (dolist (room (area-room-list area))
    (dolist (obj (container-all-objects room))
      (unless (typep obj 'mud-character)
        (create-object! world obj))))
  (dolist (conn (area-connections area))
    (create-object! world conn))
  (create-object! world area)
  ;; Record the owning world so incremental AREA-ADD-ROOM! /
  ;; AREA-REGISTER-CONNECTION! calls can register new content with it.
  (setf (area-world area) world)
  area)

(defun world-remove-area! (world area)
  "Remove AREA from WORLD's indices (not its rooms or connections, which
may be shared with other areas).  Returns AREA."
  (world-remove-object! world area))

(defun world-area-by-id (world area-id)
  "Look up an area in the world by its world-level ID."
  (gethash area-id (world-areas world)))

(defun world-all-areas (world)
  "Return the list of all areas registered in the world."
  (loop for area being the hash-values of (world-areas world)
        collect area))

(defun world-total-areas (world)
  "Return the number of areas registered in the world."
  (hash-table-count (world-areas world)))

(defun world-area-with-name (world name)
  "Return the first area in WORLD with the given NAME (case-insensitive),
or NIL."
  (loop for area being the hash-values of (world-areas world)
        when (string-equal (object-name area) name)
        return area))

(defun world-area-of-room (world room)
  "Return the area in WORLD that contains ROOM, or NIL.

Uses the room's ROOM-AREA back-reference when it points at an area
registered in WORLD (the common case); otherwise falls back to scanning
the world's areas.  The one-area-per-room invariant (enforced by
WORLD-ADD-AREA!) guarantees a room belongs to at most one area, so this
is unambiguous."
  (let ((area (room-area room)))
    (if (and area
             (eq area (world-area-by-id world (object-id area))))
        area
        (loop for candidate being the hash-values of (world-areas world)
              when (area-room-p candidate room)
              return candidate))))

(defgeneric create-object! (world object &optional room)
  (:documentation "Register OBJECT in WORLD, materializing it for persistent worlds.
For transient worlds this is equivalent to WORLD-ADD-OBJECT!.
For persistent worlds a persistent copy is created in the datastore.
When ROOM is provided, OBJECT is also placed in ROOM: its location is
set to ROOM and it is added to ROOM's contents.")
  (:method ((world mud-world) object &optional room)
    (world-add-object! world object)
    (when room
      (container-add-object room object))
    object))

(defgeneric copy-object! (world object &optional room)
  (:documentation
   "Create a copy of OBJECT, register it in WORLD, and return the copy.")
  (:method ((world mud-world) (object mud-object) &optional room)
    (let ((copy (object-copy object)))
      (create-object! world copy room)
      copy)))

