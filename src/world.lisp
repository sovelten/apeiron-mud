(in-package #:mud)

(defvar *players* (make-hash-table :test #'equal)
  "Hash table storing all active players, keyed by player object ID")

(defvar *world* nil
  "The single MUD world instance holding all persistent state")

(defclass mud-world ()
  ((id-counter :initarg :id-counter
               :accessor world-id-counter
               :initform 0
               :documentation "Monotonic ID counter for assigning world-level IDs.")
   (config :initarg :config
           :accessor world-config
           :initform (make-hash-table :test #'eq)
           :documentation "Configuration hash table (keys are keywords)."))
  (:documentation "Configuration root for the MUD world.  Rooms, guestbooks,
   and other objects are stored as independent BKNR persistent objects."))

(defun new-world () (make-instance 'mud-world))

(defun world-gen-id (world)
  ;; Increment id counter and return new id
  (incf (world-id-counter world)))

(defun world-add-room (world room)
  "Assign a world-level ID to a room and return it."
  (setf (object-id room) (world-gen-id world))
  room)

(defun world-add-object (world object)
  "Assign a world-level ID to an object and return it."
  (setf (object-id object) (world-gen-id world))
  object)

(defun world-set-starting-room (world room)
  (setf (gethash :starting-room-id (world-config world)) (object-id room)))

;; ─── Transient player management ────────────────────────────────────────────

(defun total-players ()
  (hash-table-count *players*))

(defun add-character (character)
  "Add a player to the world."
  (setf (gethash (object-id character) *players*) character))

(defun remove-character (character)
  "Remove a player from the world."
  (mud.utils:log-message "Character ~A leaving" (object-name character))
  (let ((room (object-location character)))
    (mud.utils:log-message "Removing from ~A" (object-name room))
    ;; Remove from room
    (when (typep room 'mud-room)
      (room-remove-object room character))
    ;; Remove from world
    (mud.utils:log-message "Removing ~A from world" (object-name character))
    (remhash (object-id character) *players*)
    (mud.utils:log-message "Removed")))

(defun character-by-id (char-id)
  "Get a player by ID."
  (gethash char-id *players*))

(defun characters ()
  "Get all active players."
  (loop for player being the hash-values of *players*
        collect player))

(defun find-character-in-room (room player-name)
  "Find a player in a room by name."
  (loop for obj across (room-contents room)
        when (and (typep obj 'mud-character)
                  (string-equal (object-name obj) player-name))
        return obj))

(defun world-broadcast (message &optional exclude-player)
  "Broadcast a message to all players (optionally excluding one)."
  (dolist (player (characters))
    (unless (and exclude-player (eq (object-id player) (object-id exclude-player)))
      (player-send-message player message))))

;; ─── BKNR Persistence ───────────────────────────────────────────────────────

;; ─── World queries ──────────────────────────────────────────────────────────

(defun get-config-key (key)
  "Get a configuration value from the world config."
  (gethash key (world-config *world*)))
