(in-package #:apeiron.core)

(defclass container-mixin ()
  ((contents :initarg :contents
             :accessor container-contents
             :initform (make-hash-table)
             :documentation "Container contents"))
  (:documentation "Objects that contain things inside it (character inventory, rooms)
   should use this mix-in"))

(defgeneric container-add-object (container object))
(defgeneric container-remove-object (container object))
(defgeneric container-object-by-id (container id))
(defgeneric container-all-objects (container))

(defmethod container-add-object ((container container-mixin) object)
  "Add OBJECT to CONTAINER's contents and set its location to CONTAINER.
Setting OBJECT-LOCATION is critical for BKNR persistence: on restore,
WORLD-RESTORE-OR-INITIALIZE rebuilds room contents by scanning each
persistent object's LOCATION slot."
  (setf (gethash (object-id object) (container-contents container)) object)
  (setf (object-location object) container))

(defmethod container-remove-object ((container container-mixin) object)
  "Remove OBJECT from CONTAINER's contents and clear its location."
  (remhash (object-id object) (container-contents container))
  (setf (object-location object) nil))

(defmethod container-object-by-id ((container container-mixin) id)
  (gethash id (container-contents container)))

(defmethod container-all-objects ((container container-mixin))
  (loop :for v :being :the :hash-value :of (container-contents container) :collect v))
