;;;; src/core/weapon.lisp — Weapon damage characteristics
;;;;
;;;; A weapon is any MUD-OBJECT carrying the "weapon" keyword: the hand
;;;; limbs a character is born with accept "weapon" items (see EQUIPMENT),
;;;; so holding such an object makes it the weapon in use.  A weapon's
;;;; damage is not a class slot — like every other per-object datum it
;;;; lives in object properties, so world authors set it when creating the
;;;; object and it persists with the object.  The two properties are:
;;;;
;;;;   "damage-min"   lowest damage the weapon rolls
;;;;   "damage-max"   highest damage the weapon rolls
;;;;
;;;; A weapon that defines neither falls back to the generic weapon range
;;;; below.  This file knows only about MUD-OBJECTs; the character side of
;;;; attacking (strength bonus, unarmed fallback, resolving a fight) lives
;;;; in CHARACTER.

(in-package #:apeiron.core)

(defparameter +weapon-damage-min+ 3
  "Default minimum damage for a weapon that defines no damage range.")

(defparameter +weapon-damage-max+ 8
  "Default maximum damage for a weapon that defines no damage range.")

(defun weapon-p (object)
  "Return non-NIL if OBJECT is a weapon — i.e. it carries the \"weapon\"
keyword (case-insensitive)."
  (and object
       (member "weapon" (object-keywords object) :test #'string-equal)))

(defun new-weapon (&key (name "a weapon") (description "") (aliases nil)
                        (keywords nil) (location nil)
                        (damage-min +weapon-damage-min+)
                        (damage-max +weapon-damage-max+))
  "Create a weapon, ready to be held in a hand.

The \"weapon\" keyword is added automatically, so WEAPON-P recognises the
object and it fits a hand limb; KEYWORDS are extra keywords for name
matching.  DAMAGE-MIN/DAMAGE-MAX default to the generic weapon range and
are stored as the object's \"damage-min\"/\"damage-max\" properties."
  (new-object :name name
              :description description
              :aliases aliases
              :location location
              :keywords (adjoin "weapon" keywords :test #'string-equal)
              :properties (list "damage-min" damage-min
                                "damage-max" damage-max)))

(defun weapon-damage-range (weapon)
  "Return (values MIN MAX) for WEAPON's damage roll, reading its
\"damage-min\"/\"damage-max\" properties and falling back to the generic
weapon range when either is missing.  MIN is never greater than MAX."
  (let ((min (or (object-get-property weapon "damage-min")
                 +weapon-damage-min+))
        (max (or (object-get-property weapon "damage-max")
                 +weapon-damage-max+)))
    (if (<= min max)
        (values min max)
        (values max min))))

(defun roll-damage-range (min max)
  "Return a random integer uniformly distributed across [MIN, MAX]."
  (+ min (random (1+ (- max min)))))
