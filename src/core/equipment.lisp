;;;; src/core/equipment.lisp — Body slots (limbs) for characters
;;;;
;;;; A character has a set of limbs (head, hands, feet).  Each limb is a
;;;; MUD-OBJECT and CONTAINER-MIXIN with a MAX-CAPACITY of one: its
;;;; CONTAINER-CONTENTS holds the single item worn/held there, and only
;;;; items whose KEYWORDS overlap the limb's allowed keywords
;;;; (CONTAINER-KEYWORDS) may be worn/held (e.g. a head accepts "hat",
;;;; a hand accepts "weapon").  Generic container helpers live in
;;;; CONTAINER; this file only adds the limb class and limb-specific
;;;; helpers.

(in-package #:apeiron.core)

(defclass limb (mud-object container-mixin)
  ((max-capacity :initarg :max-capacity
                 :initform 1
                 :documentation "A limb holds at most one item."))
  (:documentation "A body part that can hold or wear a single item.  The
item is stored in the limb's CONTAINER-CONTENTS; the keywords it accepts
are CONTAINER-KEYWORDS (e.g. \"hat\" for a head, \"weapon\" for a hand).
A hand limb also carries the \"hand\" keyword so HAND-LIMB-P can tell
holding limbs from wearing limbs."))

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
than worn on it.  Hands are limbs carrying the \"hand\" keyword."
  (member "hand" (object-keywords limb) :test #'string-equal))
