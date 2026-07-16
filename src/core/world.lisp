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
   (players :initarg :players
            :accessor world-players
            :initform (make-hash-table :test #'equal)
            :documentation "Stores all online/active players in world")
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
  object)

(defgeneric connect-rooms! (world room-a direction-a room-b direction-b
                            &key name blocked blocked-message synonyms-a synonyms-b)
  (:documentation "Create a bidirectional Connection between ROOM-A and ROOM-B in WORLD.

DIRECTION-A is the direction name from ROOM-A to ROOM-B (e.g. \"north\").
DIRECTION-B is the direction name from ROOM-B to ROOM-A (e.g. \"south\").
SYNONYMS-A and SYNONYMS-B are lists of alternative names for each direction
(e.g. '(\"n\") for \"north\").
When BLOCKED is true the passage starts blocked and cannot be traversed.
BLOCKED-MESSAGE is shown to players when they try to pass.

The connection is linked into both rooms' CONNECTIONS lists and
registered in the world.

Returns the registered MUD-CONNECTION instance."))

(defmethod connect-rooms! ((world mud-world) room-a direction-a room-b direction-b
                           &key (name (format nil "passage between ~A and ~A"
                                              (object-name room-a)
                                              (object-name room-b)))
                             blocked blocked-message
                             synonyms-a synonyms-b)
  (let* ((conn (make-connection room-a direction-a room-b direction-b
                                :name name :blocked blocked
                                :blocked-message blocked-message
                                :synonyms-a synonyms-a
                                :synonyms-b synonyms-b))
         (registered (create-object! world conn)))
    (push registered (room-connections room-a))
    (push registered (room-connections room-b))
    registered))

(defun connect-north-south! (world north-room south-room &rest args)
  "Connect NORTH-ROOM (left arg) south to SOUTH-ROOM (right arg).
From SOUTH-ROOM you go north to NORTH-ROOM.
Synonyms: \"s\" from north-room, \"n\" from south-room."
  (apply #'connect-rooms! world north-room "south" south-room "north"
         :synonyms-a '("s") :synonyms-b '("n")
         args))

(defun connect-west-east! (world west-room east-room &rest args)
  "Connect WEST-ROOM (left arg) east to EAST-ROOM (right arg).
From EAST-ROOM you go west to WEST-ROOM.
Synonyms: \"e\" from west-room, \"w\" from east-room."
  (apply #'connect-rooms! world west-room "east" east-room "west"
         :synonyms-a '("e") :synonyms-b '("w")
         args))

(defun world-set-starting-room! (world room)
  (setf (gethash :starting-room-id (world-config world)) (object-id room)))

(defun starting-room (world)
  "Get the starting room of the world."
  (world-room-by-id world (get-config-key world :starting-room-id)))

(defun world-add-character! (world character)
  "Add a character to the world, placing them in the starting room."
  (let ((room (starting-room world)))
    (setf (object-location character) room)
    (container-add-object room character)
    (setf (gethash (object-id character) (world-players world)) character)))

(defun world-total-players (world)
  (hash-table-count (world-players world)))

(defun world-remove-character! (world character)
  "Remove a player from the world."
  (let ((room (object-location character)))
    ;; Remove from room
    (when (typep room 'mud-room)
      (container-remove-object room character))
    ;; Remove from world
    (remhash (object-id character) (world-players world))
    (log-message "~A removed from world" (object-name character))))

(defun character-by-id (world char-id)
  "Get a player by ID."
  (gethash char-id (world-players world)))

(defun characters (world)
  "Get all active players."
  (loop for player being the hash-values of (world-players world)
        collect player))

(defun world-broadcast (world message &optional exclude-player)
  "Broadcast a message to all players (optionally excluding one)."
  (dolist (player (characters world))
    (unless (and exclude-player (eq (object-id player) (object-id exclude-player)))
      (player-send-message player message))))

;; ─── World-level object/room queries ─────────────────────────────────────

(defun world-object-by-id (world object-id)
  "Look up an object in the world by its world-level ID."
  (gethash object-id (world-objects world)))

(defun world-object-with-name (world name)
  "Return the first object in the world with the given NAME, or NIL."
  (loop for obj being the hash-values of (world-objects world)
        when (string-equal (object-name obj) name)
        return obj))

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
