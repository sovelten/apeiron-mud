(in-package #:apeiron.core)

;; Room class - a specialized mud-object

(defclass mud-room (mud-object container-mixin)
  ((exits :initarg :exits
          :accessor room-exits
          :initform (make-hash-table :test #'equal)
          :documentation "Map of exit names to target rooms")
   (connections :initarg :connections
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

(defun room-add-exit (room direction target-room)
  "Add an exit from a room to another room."
  (setf (gethash (string-downcase direction) (room-exits room)) target-room))

(defun room-add-exits (room direction target-room target-direction)
  "Add an exit from a room to another room."
  (room-add-exit room direction target-room)
  (room-add-exit target-room target-direction room))

(defun room-get-exit (room direction)
  "Get the target room for an exit."
  (gethash (string-downcase direction) (room-exits room)))

(defun room-exit-blocked-p (room player direction)
  "Return a blocking message if the player cannot use this exit yet.

Checks both flag-based gates (legacy) and Connection-based blocking."
  (let* ((dir (string-downcase direction))
         (required-flag (object-get-property room (format nil "gate-~A" dir))))
    (or (when (and required-flag (not (object-get-property player required-flag)))
          (or (object-get-property room (format nil "gate-~A-message" dir))
              (format nil "Something blocks the ~A exit. You are not ready to pass."
                      direction)))
        ;; Also check if a Connection object blocks this direction
        (connection-exit-blocked-message room direction))))

(defun room-describe (room)
  "Get a full description of a room including contents and exits."
  (let ((contents (container-all-objects room))
        (exits (loop for key being the hash-keys of (room-exits room)
                     collect (let ((conn (connection-find room key)))
                               (if (and conn (connection-blocked-p conn))
                                   (format nil "~A ~A" (yellow key) (bold-red "(blocked)"))
                                   (yellow key))))))
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
            exits)))
