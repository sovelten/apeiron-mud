(in-package #:apeiron.core)

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
          :documentation "All rooms in the world, keyed by world-level ID."))
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
Synonyms: \"s\" from north-room, \"n\" from south-room."
  (apply #'connect-rooms! world north-room south-room
         :to (add-synonym "south" "s") :from (add-synonym "north" "n")
         args))

(defun connect-west-east! (world west-room east-room &rest args)
  "Connect WEST-ROOM (left arg) east to EAST-ROOM (right arg).
From EAST-ROOM you go west to WEST-ROOM.
Synonyms: \"e\" from west-room, \"w\" from east-room."
  (apply #'connect-rooms! world west-room east-room
         :to (add-synonym "east" "e") :from (add-synonym "west" "w")
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
world-rooms).  The default method handles hash-table removal; the
persistence layer specialises this to also destroy the BKNR object.
Returns the removed OBJECT.")
  (:method (world object)
    (remhash (object-id object) (world-objects world))
    (when (typep object 'mud-character)
      (remhash (object-id object) (world-characters world)))
    (when (typep object 'mud-room)
      (remhash (object-id object) (world-rooms world)))
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

(defun world-remove-character! (world character)
  "Remove a character from the world.
Owned characters (with a non-nil OWNER) are displaced from their room
but kept in world indices. Guest characters (no owner) are completely
removed"
  (let ((name (object-name character)))
    (displace-character! character)
    (if (character-owner character)
        ;; Owned: stay in world indices
        (log-message "~A displaced from world" name)
        ;; Guest: remove from indices
        (progn
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

(defgeneric create-object! (world object)
  (:documentation "Register OBJECT in WORLD, materializing it for persistent worlds.
For transient worlds this is equivalent to WORLD-ADD-OBJECT!.
For persistent worlds a persistent copy is created in the datastore.")
  (:method ((world mud-world) object)
    (world-add-object! world object)))
