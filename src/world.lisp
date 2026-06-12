(in-package #:mud)

(defvar *players* (make-hash-table :test #'equal)
  "Hash table storing all active players, keyed by player object ID")

(defvar *system-location* #p"./prevalence/")
(defvar *system* nil)

(defclass mud-world ()
    ((id-counter :initarg :id-counter
                 :accessor world-id-counter
                 :initform 0
                 :documentation "id counter")
     (config :initarg config
             :accessor world-config
             :initform (make-hash-table)
             :documentation "Configuration hash map")
     (rooms :initarg :rooms
            :accessor world-rooms
            :initform (make-hash-table)
            :documentation "All rooms")
     (objects :initarg :objects
              :accessor world-objects
              :initform (make-hash-table)
              :documentation "All objects")
     (players :initarg :players
              :accessor world-players
              :initform (make-hash-table)
              :documentation "All players")))

(defun new-world () (make-instance 'mud-world))

(defun world-gen-id (world)
  ;; Increment id counter and return new id
  (incf (world-id-counter world)))

(defun world-add-room (world room)
  (let ((id (world-gen-id world)))
    (setf (object-id room) id)
    (setf (gethash id (world-rooms world)) room)))

(defun world-add-object (world object)
  (let ((id (world-gen-id world)))
    (setf (object-id object) id)
    (setf (gethash id (world-objects world)) object)))

(defun world-set-starting-room (world room)
  (setf (gethash :starting-room-id (world-config world)) (object-id room)))

(defun initial-world ()
  (let ((tavern (new-room :name "The Tavern" :description "There is a guestbook on top of a table. Hint: type \"write\" to write an entry on the guestbook."))
        (forest (new-room :name "A Dense Forest"))
        (guestbook (new-guestbook :name "a guestbook"))
        (world (new-world)))
    (room-add-object tavern guestbook)
    (room-add-exit tavern "north" forest)
    (room-add-exit forest "south" tavern)
    (world-add-object world guestbook)
    (world-add-room world tavern)
    (world-add-room world forest)
    (world-set-starting-room world tavern)
    world))

;; NOT PERSISTED

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

;; CL-PREVALENCE TRANSACTIONS

(defun tx-persisted-id (system)
  (let* ((counter (cl-prevalence:get-root-object system :id-counter))
         (id (incf counter)))
    (setf (cl-prevalence:get-root-object system :id-counter) id)
    id))

(defun tx-create-system (system)
  (setf (cl-prevalence:get-root-object system :rooms) (make-hash-table))
  (setf (cl-prevalence:get-root-object system :objects) (make-hash-table))
  (setf (cl-prevalence:get-root-object system :config) (make-hash-table))
  (setf (cl-prevalence:get-root-object system :id-counter) 0))

(defun tx-create-world (system world)
  (setf (cl-prevalence:get-root-object system :rooms) (world-rooms world))
  (setf (cl-prevalence:get-root-object system :objects) (world-objects world))
  (setf (cl-prevalence:get-root-object system :config) (world-config world))
  (setf (cl-prevalence:get-root-object system :id-counter) (world-id-counter world)))

(defun tx-create-object (system object)
  (let ((id (tx-persisted-id system)))
    (setf (object-id object) id)
    (setf (gethash (object-id object) (cl-prevalence:get-root-object system :objects)) object)
    object))

(defun tx-create-room (system room &optional starting?)
  (let ((id (tx-persisted-id system)))
    (setf (object-id room) id)
    (setf (gethash (object-id room) (cl-prevalence:get-root-object system :rooms)) room)
    (when starting?
      (when *debug-mode* (mud.utils:log-message "Starting room is ~A" (object-name room)))
      (setf (gethash :starting-room-id (cl-prevalence:get-root-object system :config)) (object-id room)))
    room))

(defun tx-obj-set-name (system id name)
  (let ((obj (gethash id (cl-prevalence:get-root-object system :rooms))))
    (setf (object-name obj) name)))

(defun tx-add-guestbook-entry (system room-id guestbook-id author message)
  (let ((room (gethash room-id (cl-prevalence:get-root-object system :rooms))))
    (when room
      (let ((guestbook (find-if (lambda (obj)
                                  (and (typep obj 'mud-guestbook)
                                       (= (object-id obj) guestbook-id)))
                                (room-contents room))))
        (when guestbook
          (guestbook-add-entry guestbook author message))))))

;; CL-PREVALENCE MUTATION

(defun create-room! (room)
  (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-room room))
  room)

(defun create-object! (object)
  (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-object object)))

(defun object-set-name! (id name)
  (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-obj-set-name id name)))

(defun write-guestbook-entry! (room-id guestbook-id author message)
  (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-add-guestbook-entry room-id guestbook-id author message)))

;; CL-PREVALENCE "QUERIES"

(defun total-rooms ()
  (hash-table-count (cl-prevalence:get-root-object *system* :rooms)))

(defun room-by-id (room-id)
  "Get a room from the world by ID."
  (gethash room-id (cl-prevalence:get-root-object *system* :rooms)))

(defun rooms ()
  "Get all rooms in the world."
  (let ((rooms (cl-prevalence:get-root-object *system* :rooms)))
    (if rooms
        (loop for room being the hash-values of rooms
              collect room)
        nil)))

(defun get-config-key (system key)
  (gethash key (cl-prevalence:get-root-object system :config)))

(defun starting-room (system)
  (room-by-id (get-config-key system :starting-room-id)))

(defun find-max-id ()
  "Find the maximum ID among all loaded rooms and their nested contents."
  (let ((max-id 0))
    (dolist (room (rooms))
      (setf max-id (max max-id (object-id room)))
      (loop for obj across (room-contents room)
            do (setf max-id (max max-id (object-id obj)))))
    max-id))

(defun world-restore-or-initialize (&key force-new (location *system-location*))
  "Restore the world from prevalence or initialize a new one.
If FORCE-NEW is true, any existing persisted data is cleared first."
  (when force-new
    (mud.utils:log-message "Forcing new world generation, clearing existing prevalence data...")
    (uiop:delete-directory-tree location :validate (constantly t) :if-does-not-exist :ignore))
  (setf *system* (cl-prevalence:make-prevalence-system location))
  (unless (cl-prevalence:get-root-object *system* :rooms)
    (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-system))
    (when *debug-mode* (mud.utils:log-message "Initializing world..."))
    (let ((tavern (new-room :name "The Tavern" :description "There is a guestbook on top of a table. Hint: type \"write\" to write an entry on the guestbook."))
          (forest (new-room :name "A Dense Forest"))
          (guestbook (new-guestbook :name "a guestbook")))
      (room-add-object tavern guestbook)
      (room-add-exit tavern "north" forest)
      (room-add-exit forest "south" tavern)
      (create-object! guestbook)
      (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-room tavern t))
      (cl-prevalence:execute *system* (cl-prevalence:make-transaction 'tx-create-room forest))
      (when *debug-mode* (mud.utils:log-message "Rooms created!")))))

(defun world-new-character (character)
  "Add a character to the world."
  (let ((room (starting-room *system*)))
    (setf (object-location character) room)
    (room-add-object room character)
    (add-character character)))
