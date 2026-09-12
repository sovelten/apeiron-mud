(in-package #:apeiron.core)

;; TODO: split character and player-character for building NPCs

(defun default-character-limbs ()
  "Return the standard set of limbs for a humanoid character: a head,
left and right hands, and feet.  Hand limbs carry the \"hand\" keyword
so HAND-LIMB-P can distinguish holding from wearing."
  (list (make-limb :name "head" :keywords '("hat" "helmet" "cap" "crown" "hood"))
        (make-limb :name "left hand" :keywords '("hand" "weapon"))
        (make-limb :name "right hand" :keywords '("hand" "weapon"))
        (make-limb :name "feet" :keywords '("shoe" "boot" "sandal" "slipper"))))

(defclass mud-character (mud-object container-mixin)
  ((session :initarg :session
            :accessor character-session
            :initform nil
            :documentation "The session controlling this character")
   (limbs :initarg :limbs
          :accessor character-limbs
          :initform (default-character-limbs)
          :documentation "The character limbs (hands, head(s) etc.), a list
of LIMB objects (see EQUIPMENT).  Each limb's CONTAINER-CONTENTS holds what
is currently worn/held there.  On persistent characters the limbs are
materialized into the datastore so their contents persist.")
   (account :initarg :account
            :accessor character-account
            :initform nil
            :documentation "The name (string) of the mud-account that owns this character.
NIL for guest characters.  Stored as a plain string so it survives
BKNR restarts without needing an object reference."))
  (:documentation "A character in the MUD"))

(defgeneric wear (character object &optional limb)
  (:documentation "Equip OBJECT on CHARACTER.
LIMB may be a LIMB, a limb name string (e.g. \"head\",
\"left hand\"), or NIL to wear on the first limb whose keywords fit
(reporting :occupied if that limb is already taken).

Returns (values limb reason):
  limb   — the limb equipped (or the fitting limb for :occupied /
           :keywords-dont-match), or NIL on other failures
  reason — :ok, :no-such-limb, :no-fitting-limb, :keywords-dont-match,
           :occupied, or :not-in-inventory"))

(defgeneric unequip (character object)
  (:documentation "Remove OBJECT from whichever limb holds it and return it
to CHARACTER's inventory.

Returns (values item limb), where limb is the limb it was removed from, or
(values nil nil) if OBJECT was not equipped."))

(defun new-character (name session &key account)
  (let ((character (make-instance 'mud-character
                                  :name name
                                  :session session
                                  :account account)))
    ;; Link character to session (one-way: session knows its character)
    (setf (session-character session) character)
    character))

(defun character-send-message (character message &key (newline t))
  "Send a message to a character. If NEWLINE is nil, don't add a trailing newline.
Honors the session's color preference by binding *COLORIZE* around the write.
If the character has no session (e.g. disconnected), the message is silently dropped."
  (let ((session (character-session character)))
    (when session
      (let ((*colorize* (session-use-colors session)))
        (mud-write session message :newline newline)))))

(defun find-character-in-room (room character-name)
  "Find a character in a room by name."
  (loop for obj in (container-all-objects room)
        when (and (typep obj 'mud-character)
                  (string-equal (object-name obj) character-name))
        return obj))

(defun find-limb-by-name (character name)
  "Return the limb of CHARACTER whose name matches NAME (case-insensitive),
or NIL."
  (find-if (lambda (limb) (string-equal (object-name limb) name))
           (character-limbs character)))

(defun find-limb-holding (character object)
  "Return the limb of CHARACTER currently holding OBJECT, or NIL."
  (find-if (lambda (limb) (eq (limb-item limb) object))
           (character-limbs character)))

(defun find-fitting-limb (character object)
  "Return the first limb of CHARACTER whose keywords fit OBJECT (whether
or not it is already occupied), or NIL."
  (find-if (lambda (limb) (item-fits-container-p object limb))
           (character-limbs character)))

(defun character-worn-items (character)
  "Return an alist of (LIMB . ITEM) for every item currently worn or held,
in limb order."
  (loop for limb in (character-limbs character)
        for item = (limb-item limb)
        when item
          collect (cons limb item)))

(defun character-admin-p (character)
  "Return T if CHARACTER's owning account is an administrator.
Guest characters (no account) are never administrators."
  (let ((account-name (character-account character)))
    (and account-name
         (let ((account (find-account account-name)))
           (and account (account-admin account))))))

(defun character-wearing-keywords-p (character keywords)
  "Return T if CHARACTER is currently wearing or holding an item whose
keywords include every keyword in KEYWORDS (case-insensitive)."
  (loop for pair in (character-worn-items character)
        for item = (cdr pair)
        thereis (and item
                     (every (lambda (kw)
                              (member kw (object-keywords item)
                                      :test #'string-equal))
                            keywords))))

(defun character-movement-sound (character from-room to-room direction)
  "Return the sound (e.g. \"click-clack\") made by the first item CHARACTER
is wearing or holding that reacts to moving from FROM-ROOM to TO-ROOM in
DIRECTION, or NIL if no worn item makes a sound.  See ON-MOVEMENT."
  (loop for pair in (character-worn-items character)
        for item = (cdr pair)
        for sound = (and item (on-movement item character from-room to-room direction))
        thereis sound))

(defmethod wear ((character mud-character) object &optional limb)
  "Equip OBJECT on CHARACTER — see the WEAR generic documentation."
  (let* ((requested-name (when (stringp limb) limb))
         (target (cond
                   ((typep limb 'limb) limb)
                   (requested-name (find-limb-by-name character requested-name))
                   (t (find-fitting-limb character object)))))
    (cond
      ((null target)
       (values nil (if requested-name :no-such-limb :no-fitting-limb)))
      ((not (item-fits-container-p object target))
       (values target :keywords-dont-match))
      ((not (container-empty-p target))
       (values target :occupied))
      ((not (member object (container-all-objects character) :test #'eq))
       (values nil :not-in-inventory))
      (t
       (container-remove-object character object)
       (container-add-object target object)
       ;; Worn/held items keep the CHARACTER as their canonical location
       ;; (not the limb), matching historical behavior.
       (setf (object-location object) character)
       (values target :ok)))))

(defmethod unequip ((character mud-character) object)
  "Remove OBJECT from its limb and return it to inventory — see UNEQUIP."
  (let ((limb (find-limb-holding character object)))
    (if limb
        (progn
          (container-remove-object limb object)
          (container-add-object character object)
          (values object limb))
        (values nil nil))))

(defmethod object-short-description ((obj mud-character))
  "Bright green for characters, name and ID only — no worn items."
  (bright-green (format nil "~A (ID: ~D)"
                       (object-name obj) (object-id obj))))

(defmethod object-long-description ((obj mud-character))
  "Bright green for characters, listing the description slot (if any)
and any worn/held items."
  (let ((base (bright-green (format nil "~A (ID: ~D)"
                                    (object-name obj) (object-id obj))))
        (desc (object-description obj))
        (worn (character-worn-items obj)))
    (with-output-to-string (stream)
      (format stream "~A" base)
      (when (plusp (length desc))
        (format stream "~%~A" desc))
      (when worn
        (format stream "~%~A~%~{~A~^~%~}"
                (bold-white "Wearing/holding:")
                (mapcar (lambda (pair)
                          (format nil "  - ~A (~A)"
                                  (object-short-description (cdr pair))
                                  (object-name (car pair))))
                        worn))))))

(defun guest? (character)
  (null (character-account character)))

;; ─── Stamina, derived hit points, and combat stats ──────────────────────────
;;
;; Stamina is a character's core stat.  It begins at 10 and grows as the
;; character walks (see CHARACTER-TAKE-STEP), following a Fibonacci
;; progression of step requirements.  Maximum HP is derived from stamina
;; (ten times its value), so only the stamina level and the banked step
;; count are stored — as object properties, lazily, so characters saved
;; before this system existed need no data migration.

(defconstant +character-base-stamina+ 10
  "Stamina every character starts with — the first stamina level.")

(defconstant +character-max-stamina+ 60
  "Highest stamina level a character can reach.")

(defconstant +character-hp-per-stamina+ 10
  "A character's maximum HP is this many times their stamina level.")

(defconstant +character-default-attack-min+ 4)
(defconstant +character-default-attack-max+ 9)

(defun character-stamina (character)
  "Return CHARACTER's stamina level, lazily storing the base value the
first time it is read.  Characters saved before the stamina system
existed therefore need no data migration."
  (or (object-get-property character "stamina")
      (setf (character-stamina character) +character-base-stamina+)))

(defun (setf character-stamina) (value character)
  "Set CHARACTER's stamina level, clamped to the legal range."
  (object-set-property character "stamina"
                       (max +character-base-stamina+
                            (min +character-max-stamina+ value))))

(defun character-stamina-steps (character)
  "Return how many walking steps CHARACTER has banked toward the next
stamina level.  Lazily defaults to 0."
  (or (object-get-property character "stamina-steps") 0))

(defun (setf character-stamina-steps) (value character)
  (object-set-property character "stamina-steps" (max 0 value)))

(defun stamina-steps-to-advance (level)
  "Return the number of walking steps a character at stamina LEVEL must
take to reach LEVEL+1.

The requirements follow a Fibonacci progression: 10, 10, 20, 30, 50, 80,
130, ... for levels 10, 11, 12, 13, 14, 15, 16, ... respectively."
  (let ((previous 10)
        (current 10))
    (loop for l from +character-base-stamina+ below level
          do (let ((next (+ previous current)))
               (setf previous current
                     current next)))
    previous))

(defun character-max-hp (character)
  "Return CHARACTER's maximum hit points, derived from stamina."
  (* +character-hp-per-stamina+ (character-stamina character)))

(defun character-hp (character)
  "Return CHARACTER's current hit points, defaulting lazily to maximum."
  (or (object-get-property character "hp") (character-max-hp character)))

(defun (setf character-hp) (value character)
  (object-set-property character "hp" (max 0 value)))

(defun character-ensure-combat-stats (character)
  "Give CHARACTER a current-HP value if it does not have one yet.
Maximum HP is derived from stamina (see CHARACTER-MAX-HP), so nothing
needs to be stored for it — the stat stays lazily initialized and saved
characters need no migration."
  (unless (object-get-property character "hp")
    (object-set-property character "hp" (character-max-hp character))))

(defun character-roll-attack (character)
  "Roll CHARACTER's damage for one attack."
  (declare (ignore character))
  (+ +character-default-attack-min+
     (random (1+ (- +character-default-attack-max+ +character-default-attack-min+)))))

(defun character-defeated-p (character)
  (<= (character-hp character) 0))

(defun character-heal-full (character)
  (setf (character-hp character) (character-max-hp character)))

(defun character-stamina-level-up-message ()
  "Return the (yellow) message shown when a character's stamina grows.
Deliberately free of numbers — it conveys the *feeling* of progress."
  (yellow "Something deep within you settles and strengthens. Your breath comes easier, your stride sure and tireless; the road ahead no longer daunts you."))

(defun character-take-step (character)
  "Record one walking step for CHARACTER and raise the stamina level when
enough steps have been banked.

Walking is the action tracked for stamina growth: each successful `go`
command is one step.  Returns the new stamina level when it increased,
or NIL when it did not.  A character already at +CHARACTER-MAX-STAMINA+
no longer gains levels."
  (let ((level (character-stamina character)))
    (when (>= level +character-max-stamina+)
      (return-from character-take-step nil))
    (let* ((required (stamina-steps-to-advance level))
           (steps (1+ (character-stamina-steps character))))
      (if (>= steps required)
          (progn
            (setf (character-stamina-steps character) (- steps required))
            (setf (character-stamina character) (1+ level))
            ;; Maximum HP just grew with the new level: grant the character
            ;; the gained hit points, unless HP has not been initialized
            ;; yet (then it is filled lazily at the new maximum).
            (let ((hp (object-get-property character "hp")))
              (when hp
                (object-set-property character "hp"
                                     (+ hp +character-hp-per-stamina+))))
            (1+ level))
          (progn
            (setf (character-stamina-steps character) steps)
            nil)))))
