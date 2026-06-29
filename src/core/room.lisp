(in-package #:apeiron.core)

;; Room class - a specialized mud-object

(defclass mud-room (mud-object)
  ((contents :initarg :contents
             :accessor room-contents
             :initform (make-array 0 :adjustable t :fill-pointer t)
             :documentation "Objects contained in this room")
   (exits :initarg :exits
          :accessor room-exits
          :initform (make-hash-table :test #'equal)
          :documentation "Map of exit names to target rooms"))
  (:documentation "A location/room in the MUD"))

(defun new-room (&key (name "A Room") (description ""))
  "Create a new room."
  (make-instance 'mud-room
                 :name name
                 :description description
                 :type +object-type-room+
                 :location nil))

(defun room-add-object (room obj)
  "Add an object to a room and set its location."
  (let ((contents (room-contents room)))
    (unless (and (vectorp contents) (array-has-fill-pointer-p contents))
      (setf contents (make-array (length contents)
                                 :adjustable t
                                 :fill-pointer (length contents)
                                 :initial-contents contents))
      (setf (room-contents room) contents))
    (vector-push-extend obj contents))
  (setf (object-location obj) room))

(defun room-remove-object (room obj)
  "Remove an object from a room and clear its location."
  (let ((contents (room-contents room)))
    (unless (and (vectorp contents) (array-has-fill-pointer-p contents))
      (setf contents (make-array (length contents)
                                 :adjustable t
                                 :fill-pointer (length contents)
                                 :initial-contents contents))
      (setf (room-contents room) contents))
    (loop for i from 0 below (fill-pointer contents)
          do (when (eq (aref contents i) obj)
               (loop for j from i below (1- (fill-pointer contents))
                     do (setf (aref contents j) (aref contents (1+ j))))
               (decf (fill-pointer contents))
               (return))))
  (when (eq (object-location obj) room)
    (setf (object-location obj) nil)))

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
  (let ((contents (room-contents room))
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
            (map 'list (lambda (obj)
                         (format nil "  - ~A" (object-describe obj)))
                 contents)
            ;; "Exits:" header
            (bold-white "Exits: ")
            ;; Exit directions — yellow
            (mapcar #'yellow exits))))
