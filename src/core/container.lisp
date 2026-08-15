(in-package #:apeiron.core)

(defclass container-mixin ()
  ((contents :initarg :contents
             :accessor container-contents
             :initform nil
             :documentation "Container contents: a list of the contained
objects.  A list (rather than a hash keyed by OBJECT-ID) so that objects
which have not yet been registered with a world — and therefore share
the unset OBJECT-ID -1 — can still coexist in one container.")
   (max-capacity :initarg :max-capacity
                 :accessor container-max-capacity
                 :initform nil
                 :documentation "Maximum number of objects this container
may hold, or NIL for no limit.  Limbs use a capacity of 1.")
   (keywords :initarg :keywords
             :accessor container-keywords
             :initform nil
             :documentation "List of item keywords that are allowed in this
container (e.g. \"hat\" for a head limb, \"weapon\" for a hand limb).
Only meaningful for containers that restrict what may be stored; rooms
and inventories leave it NIL."))
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
not clobber one another.

Returns T on success, or NIL if CONTAINER is already at MAX-CAPACITY."
  (let ((capacity (container-max-capacity container)))
    (when (or (null capacity)
              (< (length (container-contents container)) capacity))
      (let ((contents (container-contents container)))
        (pushnew object contents :test #'eq)
        (setf (container-contents container) contents))
      (setf (object-location object) container)
      t)))

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
  (loop for obj in (container-contents container)
        when (object-name-matches obj name)
        collect obj))
