(in-package #:mud)

;; Global world data structure
(defvar *world* (make-hash-table :test #'equal)
  "Hash table storing all rooms in the world, keyed by room ID")

(defvar *players* (make-hash-table :test #'equal)
  "Hash table storing all active players, keyed by player object ID")

(defvar *start-room* nil
  "The starting room for new players")

(defun world-add-room (room)
  "Add a room to the world."
  (setf (gethash (object-id room) *world*) room)
  room)

(defun world-get-room (room-id)
  "Get a room from the world by ID."
  (gethash room-id *world*))

(defun world-all-rooms ()
  "Get all rooms in the world."
  (loop for room being the hash-values of *world*
        collect room))

(defun world-initialize ()
  "Initialize the world with basic structure."
  (when *debug-mode*
    (mud.utils:log-message "Initializing world..."))
  
  ;; Create starting room
  (let ((start-room (create-room :name "The Tavern")))
    (world-add-room start-room)
    (setf *start-room* start-room))
  
  ;; Create a second room
  (let ((forest (create-room :name "A Dense Forest")))
    (world-add-room forest)
    ;; Connect rooms
    (room-add-exit *start-room* "north" forest)
    (room-add-exit forest "south" *start-room*))
  
  (when *debug-mode*
    (mud.utils:log-message "World initialized with ~D rooms" 
                          (hash-table-count *world*)))
  t)

(defun world-add-player (player)
  "Add a player to the world."
  (setf (gethash (object-id player) *players*) player))

(defun world-new-character (character)
  "Add a character to the world."
  (when *start-room*
      (room-add-object *start-room* character))
  (world-add-player character))

(defun world-remove-player (player)
  "Remove a player from the world."
  (mud.utils:log-message "Character ~A leaving" (object-name player))
  (let ((room (object-location player)))
    (mud.utils:log-message "Removing from ~A" (object-name room))
    ;; Remove from room
    (when (typep room 'mud-room)
      (room-remove-object room player))
    ;; Remove from world
    (mud.utils:log-message "Removing ~A from world" (object-name player))
    (remhash (object-id player) *players*)
    (mud.utils:log-message "Removed")))

(defun world-get-player (player-id)
  "Get a player by ID."
  (gethash player-id *players*))

(defun world-all-players ()
  "Get all active players."
  (loop for player being the hash-values of *players*
        collect player))

(defun world-get-player-in-room (room player-name)
  "Find a player in a room by name."
  (loop for obj across (room-contents room)
        when (and (typep obj 'mud-character)
                  (string-equal (object-name obj) player-name))
        return obj))

(defun world-broadcast (message &optional exclude-player)
  "Broadcast a message to all players (optionally excluding one)."
  (dolist (player (world-all-players))
    (unless (and exclude-player (eq (object-id player) (object-id exclude-player)))
      (player-send-message player message))))
