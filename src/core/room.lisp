(in-package #:apeiron.core)

;; Room class - a specialized mud-object

(defclass mud-room (mud-object container-mixin)
  ((connections :initarg :connections
                :accessor room-connections
                :initform '()
                :documentation "List of Connection objects attached to this room"))
  (:documentation "A location/room in the MUD"))

(defun new-room (&key (name "A Room") (description ""))
  "Create a new room."
  (make-instance 'mud-room
                 :name name
                 :description description
                 
                 :location nil))

(defun find-character-in-room (room player-name)
  "Find a player in a room by name."
  (loop for obj in (container-all-objects room)
        when (and (typep obj 'mud-character)
                  (string-equal (object-name obj) player-name))
        return obj))

(defun room-exit-target (room direction)
  "Get the target room when moving in DIRECTION from ROOM.

Returns the room at the other end of the matching Connection, or NIL."
  (let ((conn (connection-find room direction)))
    (when conn
      (connection-other-room conn room))))

(defun room-exit-list (room)
  "Return a list of (direction connection) for every exit in ROOM.

DIRECTION is a lowercase string, CONNECTION is the MUD-CONNECTION."
  (loop for conn in (room-connections room)
        collect (list (connection-direction-to conn room) conn)))

(defun room-exit-blocked-p (room player direction)
  "Return a blocking message if the player cannot use this exit yet.

First checks if the connection itself is blocked (covers challenges,
riddles, and any other reason a connection might be impassable).
Then falls back to flag-based gates stored on the room."
  (let ((dir (string-downcase direction)))
    (or
     ;; Connection-based blocking (challenges, riddles, locked doors)
     (connection-exit-blocked-message room dir)
     ;; Flag-based gate (e.g. defeat an NPC to pass) — stored on the room
     (let ((required-flag (object-get-property room (format nil "gate-~A" dir))))
       (when (and required-flag (not (object-get-property player required-flag)))
         (or (object-get-property room (format nil "gate-~A-message" dir))
             (format nil "Something blocks the ~A exit. You are not ready to pass."
                     direction)))))))

(defun room-describe (room)
  "Get a full description of a room including contents and exits."
  (let ((contents (container-all-objects room))
        (exits (room-exit-list room)))
    (format nil "~%~A~%~A~%~A~%~{~A~%~}~%~A~{~A~^, ~}~%"
            ;; Room name — bold bright white
            (bold-white (format nil "=== ~A ===" (object-name room)))
            ;; Room description — keep default (no color)
            (object-description room)
            ;; "You see:" header
            (bold-white "You see:")
            ;; Contents — color-coded by type
            (mapcar (lambda (obj)
                      (format nil "  - ~A" (object-describe obj)))
                    contents)
            ;; "Exits:" header
            (bold-white "Exits: ")
            ;; Exit directions — yellow, with (blocked) suffix if applicable
            (mapcar (lambda (exit-pair)
                      (let ((dir (first exit-pair))
                            (conn (second exit-pair)))
                        (if (and conn (connection-blocked-p conn))
                            (format nil "~A ~A" (yellow dir) (bold-red "(blocked)"))
                            (yellow dir))))
                    exits))))
