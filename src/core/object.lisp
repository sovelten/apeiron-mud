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
   (location :initarg :location
             :accessor object-location
             :initform nil
             :documentation "Location/container of this object")
   (aliases :initarg :aliases
            :accessor object-aliases
            :initform nil
            :documentation "List of alternative name strings for matching")
   (properties :initarg :properties
               :accessor object-properties
               :initform (make-hash-table :test #'equal)
               :documentation "Extensible property storage"))
  (:documentation "Base class for all MUD objects"))

(defgeneric object-describe (obj)
  (:documentation
   "Get a description of an object with type-based ANSI coloring.
Specialized methods on subclasses provide appropriate coloring."))

(defgeneric object-set-property (obj property-name value)
  (:documentation
   "Set a property value on an object.

The default method modifies the hash-table in-place.

Specialized methods on persistent objects should also ensure the slot
is written so BKNR's transaction logging captures the change."))

(defun new-object (&key (name "object") (location nil))
  "Create a new MUD object."
  (make-instance 'mud-object
                 :name name
                 :location location))

(defun object-name-matches (obj name)
  "Return non-NIL if NAME matches the object's primary name or any alias (case-insensitive)."
  (or (string-equal name (object-name obj))
      (some (lambda (alias) (string-equal name alias))
            (object-aliases obj))))

(defun object-get-property (obj property-name)
  "Get a property value from an object."
  (gethash property-name (object-properties obj)))

(defmethod object-set-property (obj property-name value)
  "Default: modify the properties hash-table in-place."
  (setf (gethash property-name (object-properties obj)) value))

(defun object-move (obj new-location)
  "Move an object to a new location."
  (let ((old-location (object-location obj)))
    ;; Remove from old location if it's a room
    (when (and old-location (typep old-location 'mud-room))
      (container-remove-object old-location obj))
    ;; Set new location
    (setf (object-location obj) new-location)
    ;; Add to new location if it's a room
    (when (typep new-location 'mud-room)
      (container-add-object new-location obj))
    t))

(defmethod object-describe ((obj mud-object))
  "Default: no color."
  (format nil "~A (ID: ~D)" (object-name obj) (object-id obj)))

;; Print object in REPL with useful information
(defmethod print-object ((obj mud-object) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~A (ID: ~D)"
            (object-name obj)
            (object-id obj))))
