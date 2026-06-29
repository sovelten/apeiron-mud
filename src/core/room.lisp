(in-package #:apeiron.core)

;; Room class - a specialized mud-object

(defclass mud-room (mud-object container-mixin)
  ((exits :initarg :exits
          :accessor room-exits
          :initform (make-hash-table :test #'equal)
          :documentation "Map of exit names to target rooms"))
  (:documentation "A location/room in the MUD"))

(defun new-room (&key (name "A Room") (description ""))
  "Create a new room."
  (make-instance 'mud-room
                 :name name
                 :description description
                 
                 :location nil))

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

(defun room-describe (room)
  "Get a full description of a room including contents and exits."
  (let ((contents (container-all-objects room))
        (exits (loop for key being the hash-keys of (room-exits room)
                     collect key)))
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
            ;; Exit directions — yellow
            (mapcar #'yellow exits))))
