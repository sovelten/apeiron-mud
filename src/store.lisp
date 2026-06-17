(in-package :mud)

(defclass wrapping-persistent-class (bknr.datastore:persistent-class)
  ((transient-slots :initarg :transient-slots
                    :initform nil
                    :accessor class-transient-slots
                    :documentation "List of slot names inherited from
                    non-persistent parents that should be treated as
                    transient (not stored in the datastore)."))
  (:documentation
   "A persistent-class that can safely inherit slots from a non-persistent
    standard-class parent."))

(defmethod sb-mop:validate-superclass
    ((sub   wrapping-persistent-class)
     (super sb-mop:standard-class))
  t)

(defun upgrade-to-persistent-slot (slotd &key transient)
  "Convert a non-persistent direct-slot-definition to a
persistent-direct-slot-definition, preserving all attributes
(including index information from index-direct-slot-definition)."
  (let ((common
          (list :name (sb-mop:slot-definition-name slotd)
                :initform (sb-mop:slot-definition-initform slotd)
                :initfunction (sb-mop:slot-definition-initfunction slotd)
                :type (sb-mop:slot-definition-type slotd)
                :allocation (sb-mop:slot-definition-allocation slotd)
                :readers (sb-mop:slot-definition-readers slotd)
                :writers (sb-mop:slot-definition-writers slotd)
                :initargs (sb-mop:slot-definition-initargs slotd)
                :transient transient)))
    (if (typep slotd 'bknr.indices:index-direct-slot-definition)
        (apply #'make-instance 'bknr.datastore::persistent-direct-slot-definition
               (nconc common
                      (list :index (bknr.indices::index-direct-slot-definition-index slotd)
                            :index-var (bknr.indices::index-direct-slot-definition-index-var slotd)
                            :index-type (bknr.indices::index-direct-slot-definition-index-type slotd)
                            :index-initargs (bknr.indices::index-direct-slot-definition-index-initargs slotd)
                            :index-reader (bknr.indices::index-direct-slot-definition-index-reader slotd)
                            :index-values (bknr.indices::index-direct-slot-definition-index-values slotd)
                            :index-mapvalues (bknr.indices::index-direct-slot-definition-index-mapvalues slotd)
                            :index-keys (bknr.indices::index-direct-slot-definition-index-keys slotd)
                            :index-subclasses (bknr.indices::index-direct-slot-definition-index-subclasses slotd))))
        (apply #'make-instance 'bknr.datastore::persistent-direct-slot-definition common))))

(defmethod sb-mop:compute-effective-slot-definition :around
    ((class wrapping-persistent-class) name direct-slots)
  ;; Convert any inherited non-persistent direct-slot-definition instances
  ;; (standard-direct-slot-definition or index-direct-slot-definition)
  ;; into persistent-direct-slot-definition instances so that bknr's own
  ;; :around method can safely read the :transient slot.
  ;; Slots listed in (class-transient-slots class) are marked transient;
  ;; all others are persistent.
  (let* ((transient-slot-names (class-transient-slots class))
         (fixed-slots
          (mapcar (lambda (slotd)
                    (if (typep slotd 'bknr.datastore::persistent-direct-slot-definition)
                        ;; Already persistent — leave as-is
                        slotd
                        ;; Convert to persistent while preserving index attrs
                        (upgrade-to-persistent-slot
                         slotd
                         :transient (if (member (sb-mop:slot-definition-name slotd)
                                                transient-slot-names)
                                        t
                                        nil))))
                  direct-slots)))
    (call-next-method class name fixed-slots)))

(defmethod (setf sb-mop:slot-value-using-class) :around
    (newval (class wrapping-persistent-class) object
            (slotd bknr.datastore::persistent-effective-slot-definition))
  ;; Automatically wrap persistent slot writes in a transaction so that
  ;; vanilla accessor functions like (setf (object-name obj) "x") work
  ;; without explicit transaction wrapping.
  ;; Transient slots are left alone — they can be set freely already.
  ;; The auto-wrap transaction gets a descriptive label so it shows up
  ;; informatively in the transaction log.
  (if (or (bknr.datastore:in-transaction-p)
          (bknr.datastore::transient-slot-p slotd))
      (call-next-method)
      (bknr.datastore:with-transaction
          ((format nil "auto-wrap ~A" (sb-mop:slot-definition-name slotd)))
        (call-next-method))))

(defmacro defwrapping-persistent-class (class superclasses slots &rest class-options)
  "Like BKNR.DATASTORE:DEFPERSISTENT-CLASS but uses
WRAPPING-PERSISTENT-CLASS as the metaclass, so SUPERCLASSES can include
vanilla STANDARD-CLASS parents whose slots lack :TRANSIENT annotations.
STORE-OBJECT is automatically prepended to the superclass list.

Class option `:transient-slots` — list of slot names inherited from
non-persistent parents that should NOT be stored in the datastore.
All other inherited slots are persistent by default.

Example:
  (defwrapping-persistent-class my-persistent (my-class)
    ()
    (:transient-slots name cached-data))"
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (defclass ,class ,(append superclasses '(bknr.datastore:store-object))
       ,slots
       (:metaclass wrapping-persistent-class)
       ,@class-options)))
