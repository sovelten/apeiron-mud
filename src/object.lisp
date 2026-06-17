(in-package #:mud)

(defclass mud-object ()
  ((id :initarg :id
       :initform (mud.utils:make-id)
       :accessor object-id
       :documentation "Unique identifier for this object")
   (name :initarg :name
         :index-type bknr.indices:hash-index
         :index-initargs (:test #'equal)
         :index-reader object-with-name
         :index-values all-objects
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
  (:documentation "Base class for all MUD objects")
  (:metaclass bknr.indices:indexed-class))

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
  "Get a description of an object."
  (format nil "~A (ID: ~D)" (object-name obj) (object-id obj)))

;; Print object in REPL with useful information
(defmethod print-object ((obj mud-object) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~A (ID: ~D)"
            (object-name obj)
            (if (typep obj 'bknr.datastore:store-object)
                    (bknr.datastore:store-object-id obj)
                    (object-id obj)))))
