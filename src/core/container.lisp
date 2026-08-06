(in-package #:apeiron.core)

(defclass container-mixin ()
  ((contents :initarg :contents
             :accessor container-contents
             :initform nil
             :documentation "Container contents: a list of the contained
objects.  A list (rather than a hash keyed by OBJECT-ID) so that objects
which have not yet been registered with a world — and therefore share
the unset OBJECT-ID -1 — can still coexist in one container."))
  (:documentation "Objects that contain things inside it (character inventory, rooms)
   should use this mix-in"))

(defgeneric container-add-object (container object))
(defgeneric container-remove-object (container object))
(defgeneric container-object-by-id (container id))
(defgeneric container-all-objects (container))
(defgeneric container-objects-matching (container name))

(defmethod container-add-object ((container container-mixin) object)
  "Add OBJECT to CONTAINER's contents and set its location to CONTAINER.
Setting OBJECT-LOCATION is critical for BKNR persistence: on restore,
WORLD-RESTORE-OR-INITIALIZE rebuilds room contents by scanning each
persistent object's LOCATION slot.

The contents list is keyed by object identity, so adding the same object
twice is idempotent and objects that share an unset OBJECT-ID (-1) do
not clobber one another."
  (pushnew object (container-contents container) :test #'eq)
  (setf (object-location object) container))

(defmethod container-remove-object ((container container-mixin) object)
  "Remove OBJECT from CONTAINER's contents and clear its location."
  (setf (container-contents container)
        (remove object (container-contents container) :test #'eq))
  (setf (object-location object) nil))

(defmethod container-object-by-id ((container container-mixin) id)
  "Return the object in CONTAINER with the given world-level ID, or NIL.
Linear scan over the contents list (containers are small; this lookup
is used rarely, mostly by tests)."
  (find id (container-contents container)
        :key #'object-id :test #'eql))

(defmethod container-all-objects ((container container-mixin))
  "Return the list of all objects in CONTAINER."
  (container-contents container))

(defmethod container-objects-matching ((container container-mixin) name)
  "Return a list of objects in CONTAINER whose name or alias matches NAME."
  (loop for obj in (container-all-objects container)
        when (object-name-matches obj name)
        collect obj))
