;;;; src/core/human.lisp — Body slots (limbs) for characters
;;;;
;;;; A character has a set of limbs (head, hands, ...).  Each limb is an
;;;; ITEM-SLOT-MIXIN: it holds at most one item, and only items whose
;;;; KEYWORDS overlap the limb's allowed keywords may be worn/held there
;;;; (e.g. a head accepts "hat", a hand accepts "weapon").

(in-package #:apeiron.core)

(defclass item-slot-mixin ()
  ((name :initarg :name
         :accessor item-slot-name
         :initform "a body slot"
         :documentation "Human-readable name of this slot (e.g. \"head\",
\"left hand\")")
   (keywords :initarg :keywords
             :accessor item-slot-keywords
             :initform nil
             :documentation "List of item keywords that are allowed in this
slot (e.g. \"hat\" for a head, \"weapon\" for a hand)")
   (item :initarg :item
         :accessor item-slot
         :initform nil
         :documentation "The single item currently held/worn in this slot,
or NIL when the slot is empty"))
  (:documentation "A body slot that can hold a single item.  An item may be
equipped here only if its keywords overlap ITEM-SLOT-KEYWORDS."))

(defgeneric item-slot-add (slot object)
  (:documentation "Place OBJECT in SLOT if the slot is empty and OBJECT's
keywords fit.  Returns OBJECT on success, NIL otherwise."))

(defgeneric item-slot-remove (slot object)
  (:documentation "Remove OBJECT from SLOT if it is the item held there.
Returns OBJECT on success, NIL otherwise."))

(defmethod item-slot-add ((slot item-slot-mixin) object)
  "Place OBJECT in SLOT if empty and fitting."
  (when (and (null (item-slot slot))
             (item-fits-slot-p object slot))
    (setf (item-slot slot) object)
    object))

(defmethod item-slot-remove ((slot item-slot-mixin) object)
  "Remove OBJECT from SLOT if it is the item held there."
  (when (eq (item-slot slot) object)
    (setf (item-slot slot) nil)
    object))

(defun item-slot-empty-p (slot)
  "Return non-NIL if SLOT currently holds no item."
  (null (item-slot slot)))

(defun item-slot-occupied-p (slot)
  "Return non-NIL if SLOT currently holds an item."
  (not (item-slot-empty-p slot)))

(defun item-fits-slot-p (object slot)
  "Return non-NIL if OBJECT's keywords overlap SLOT's allowed keywords.

An item with no keywords fits no slot: it cannot be worn or held anywhere."
  (intersection (object-keywords object)
                (item-slot-keywords slot)
                :test #'string-equal))

(defclass head (item-slot-mixin)
  ()
  (:documentation "A head: wears hats, helmets, caps, crowns, hoods, etc."))

(defclass hand (item-slot-mixin)
  ()
  (:documentation "A hand: holds weapons."))

(defun make-head (&key (name "head"))
  "Create a head limb.  Accepts hats, helmets, caps, crowns and hoods."
  (make-instance 'head
                 :name name
                 :keywords '("hat" "helmet" "cap" "crown" "hood")))

(defun make-hand (&key (name "hand"))
  "Create a hand limb.  Holds weapons."
  (make-instance 'hand
                 :name name
                 :keywords '("weapon")))
