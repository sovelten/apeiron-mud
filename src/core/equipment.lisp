;;;; src/core/equipment.lisp — Body slots (limbs) for characters
;;;;
;;;; A character has a set of limbs (head, hands, ...).  Each limb is a
;;;; MUD-OBJECT and CONTAINER-MIXIN with a MAX-CAPACITY of one: its
;;;; CONTAINER-CONTENTS holds the single item worn/held there, and only
;;;; items whose KEYWORDS overlap the limb's allowed keywords
;;;; (CONTAINER-KEYWORDS) may be worn/held (e.g. a head accepts "hat",
;;;; a hand accepts "weapon").

(in-package #:apeiron.core)

(defclass limb (mud-object container-mixin)
  ((max-capacity :initarg :max-capacity
                 :initform 1
                 :documentation "A limb holds at most one item."))
  (:documentation "A body part that can hold or wear a single item.  The
item is stored in the limb's CONTAINER-CONTENTS; the keywords it accepts
are CONTAINER-KEYWORDS (e.g. \"hat\" for a head, \"weapon\" for a hand)."))

(defun limb-empty-p (limb)
  "Return non-NIL if LIMB currently holds no item."
  (null (container-contents limb)))

(defun limb-occupied-p (limb)
  "Return non-NIL if LIMB currently holds an item."
  (not (limb-empty-p limb)))

(defun item-fits-limb-p (object limb)
  "Return non-NIL if OBJECT's keywords overlap LIMB's allowed keywords.

An item with no keywords fits no limb: it cannot be worn or held anywhere."
  (intersection (object-keywords object)
                (container-keywords limb)
                :test #'string-equal))

(defun make-limb (&key (name "limb") (keywords nil))
  "Create a limb.  KEYWORDS are the item keywords allowed in it."
  (make-instance 'limb
                 :name name
                 :keywords keywords))

(defun limb-item (limb)
  "Return the single item currently held/worn in LIMB, or NIL."
  (first (container-contents limb)))

(defun hand-limb-p (limb)
  "Return non-NIL if LIMB is a hand — i.e. an item is held in it rather
than worn on it.  Hands are limbs whose name contains \"hand\"."
  (search "hand" (object-name limb) :test #'string-equal))
