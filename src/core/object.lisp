(in-package #:apeiron.core)

(defclass mud-object ()
  ((id :initarg :id
       :initform -1 ;; Set id when added to world
       :accessor object-id
       :documentation "Unique identifier for this object")
   (name :initarg :name
         :accessor object-name
         :initform "unnamed object"
         :documentation "Display name of the object")
   (description :initarg :description
                :accessor object-description
                :initform ""
                :documentation "Object description")
   (type :initarg :type
         :accessor object-type
         :initform +object-type-generic+
         :documentation "Type of object (generic, room, player, item, etc.)")
   (location :initarg :location
             :accessor object-location
             :initform nil
             :documentation "Location/container of this object")
   (properties :initarg :properties
               :accessor object-properties
               :initform (make-hash-table :test #'equal)
               :documentation "Extensible property storage"))
  (:documentation "Base class for all MUD objects"))

(defun new-object (&key (name "object") (type +object-type-generic+) (location nil))
  "Create a new MUD object."
  (make-instance 'mud-object
                 :name name
                 :type type
                 :location location))

(defun object-get-property (obj property-name)
  "Get a property value from an object."
  (gethash property-name (object-properties obj)))

(defun object-set-property (obj property-name value)
  "Set a property value on an object."
  (setf (gethash property-name (object-properties obj)) value))

(defun object-move (obj new-location)
  "Move an object to a new location."
  (let ((old-location (object-location obj)))
    ;; Remove from old location if it's a room
    (when (and old-location (typep old-location 'mud-room))
      (room-remove-object old-location obj))
    ;; Set new location
    (setf (object-location obj) new-location)
    ;; Add to new location if it's a room
    (when (typep new-location 'mud-room)
      (room-add-object new-location obj))
    t))

(defun object-describe (obj)
  "Get a description of an object with type-based ANSI coloring.
- Characters (players): bright green
- NPCs: bright red
- Items: cyan
- Rooms: bold white
- Generic: default (no color)"
  (let ((name (object-name obj)))
    (cond
      ((typep obj 'mud-npc)
       (bright-red (format nil "~A (ID: ~D)" name (object-id obj))))
      ((eq (object-type obj) +object-type-character+)
       (bright-green (format nil "~A (ID: ~D)" name (object-id obj))))
      ((eq (object-type obj) +object-type-item+)
       (cyan (format nil "~A (ID: ~D)" name (object-id obj))))
      ((eq (object-type obj) +object-type-room+)
       (bold-white (format nil "~A (ID: ~D)" name (object-id obj))))
      (t
       (format nil "~A (ID: ~D)" name (object-id obj))))))

;; Print object in REPL with useful information
(defmethod print-object ((obj mud-object) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~A (ID: ~D)"
            (object-name obj)
            (object-id obj))))
