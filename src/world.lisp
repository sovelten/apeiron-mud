(in-package #:mud)

;; Global world data structure
(defvar *world* (make-hash-table :test #'equal)
  "Hash table storing all rooms in the world, keyed by room ID")

(defvar *players* (make-hash-table :test #'equal)
  "Hash table storing all active players, keyed by player object ID")

(defvar *system* nil)

(defun total-players ()
  (hash-table-count *players*))

(defun total-rooms ()
  (hash-table-count (cl-prevalence:get-root-object *system* :rooms)))

(defun tx-create-room (system room &optional starting?)
  (setf (gethash (object-id room) (cl-prevalence:get-root-object system :rooms)) room)
  (when starting?
    (when *debug-mode* (mud.utils:log-message "Starting room is ~A" (object-name room)))
    (setf (gethash :starting-room-id (cl-prevalence:get-root-object system :config)) (object-id room))))

(defun create-room! (room)
  (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-room room))
  room)

(defun tx-create-system (system)
  (setf (cl-prevalence:get-root-object system :rooms) (make-hash-table))
  (setf (cl-prevalence:get-root-object system :config) (make-hash-table)))

(defun world-get-room (room-id)
  "Get a room from the world by ID."
  (gethash room-id (cl-prevalence:get-root-object *system* :rooms)))

(defun world-all-rooms ()
  "Get all rooms in the world."
  (let ((rooms (cl-prevalence:get-root-object *system* :rooms)))
    (loop for room being the hash-values of rooms
          collect room)))

(defun get-config-key (system key)
  (gethash key (cl-prevalence:get-root-object system :config)))

(defun starting-room (system)
  (world-get-room (get-config-key system :starting-room-id)))

(defun world-restore-or-initialize ()
  (setf *system* (cl-prevalence:make-prevalence-system #p"./prevalence/"))
  (unless (cl-prevalence:get-root-object *system* :rooms)
    (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-system))
    (when *debug-mode* (mud.utils:log-message "Initializing world..."))
    (let ((tavern (create-room :name "The Tavern"))
          (forest (create-room :name "A Dense Forest")))
      (room-add-exit tavern "north" forest)
      (room-add-exit forest "south" tavern)
      (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-room tavern t))
      (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-room forest))
      (when *debug-mode* (mud.utils:log-message "Rooms created!")))))

(defun world-add-player (player)
  "Add a player to the world."
  (setf (gethash (object-id player) *players*) player))

(defun tx-new-character (system character)
  "Add a character to the world."
  (let ((room (starting-room system)))
    (setf (object-location character) room)
    (room-add-object room character)
    (world-add-player character)))

(defun world-new-character (character)
  "Add a character to the world."
  (let ((room (starting-room *system*)))
    (setf (object-location character) room)
    (room-add-object room character)
    (world-add-player character)))

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
