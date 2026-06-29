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
  (setf (gethash (object-id object) (container-contents container)) object))

(defmethod container-remove-object ((container container-mixin) object)
  (remhash (object-id object) (container-contents container)))

(defmethod container-object-by-id ((container container-mixin) id)
  (gethash id (container-contents container)))

(defmethod container-all-objects ((container container-mixin))
  (loop :for v :being :the :hash-value :of (container-contents container) :collect v))
