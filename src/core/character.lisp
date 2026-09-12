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

;; ─── Character stats, levelling, and derived hit points ─────────────────────
;;
;; A stat is a named level that grows from a character's actions.  Every
;; stat follows the same rule: it starts at +CHARACTER-BASE-STAT+, can
;; reach at most +CHARACTER-MAX-STAT+, and each new level costs a number
;; of points given by a Fibonacci progression (10, 10, 20, 30, 50, 80,
;; 130, ... for levels 10, 11, 12, ...).  This section owns that mechanism
;; once; adding a stat means naming it and, if it has side effects,
;; specializing CHARACTER-STAT-LEVEL-UP! and CHARACTER-STAT-LEVEL-UP-MESSAGE.
;;
;; Stamina grows by walking (one point per successful `go`); intelligence
;; grows by solving Wordle puzzles (ten points per solve).  Maximum HP is
;; derived from stamina.
;;
;; Levels and banked points are stored as object properties, lazily, so
;; characters saved before a stat existed need no data migration.

(defparameter +character-base-stat+ 10
  "Level every character stat starts at.")

(defparameter +character-max-stat+ 60
  "Highest level a character stat can reach.")

(defparameter +character-hp-per-stamina+ 10
  "A character's maximum HP is this many times their stamina level.")

(defparameter +character-default-attack-min+ 4)
(defparameter +character-default-attack-max+ 9)

;; ─── Stat designators and storage ───────────────────────────────────────────

(defun stat-key (stat)
  "Canonicalize STAT — a keyword, symbol, or string — to a keyword."
  (intern (string-upcase (string stat)) :keyword))

(defun stat-property (stat)
  "The object property name holding STAT's current level."
  (string-downcase (string (stat-key stat))))

(defun stat-points-property (stat)
  "The object property name holding STAT's banked progress."
  (concatenate 'string (stat-property stat) "-points"))

(defun stat-points-to-advance (level)
  "Return how many points a stat at LEVEL needs to reach LEVEL+1.

The requirements follow a Fibonacci progression: 10, 10, 20, 30, 50, 80,
130, ... for levels 10, 11, 12, 13, 14, 15, 16, ... respectively."
  (let ((previous 10)
        (current 10))
    (loop for l from +character-base-stat+ below level
          do (let ((next (+ previous current)))
               (setf previous current
                     current next)))
    previous))

(defun character-stat (character stat)
  "Return CHARACTER's level in STAT, lazily storing the base value the
first time it is read, so saved characters need no data migration."
  (let ((property (stat-property stat)))
    (or (object-get-property character property)
        (let ((base +character-base-stat+))
          (object-set-property character property base)
          base))))

(defun (setf character-stat) (value character stat)
  "Set CHARACTER's level in STAT, clamped to the legal range."
  (let ((level (max +character-base-stat+
                    (min +character-max-stat+ value))))
    (object-set-property character (stat-property stat) level)
    level))

(defun character-stat-points (character stat)
  "Return the points CHARACTER has banked toward STAT's next level."
  (or (object-get-property character (stat-points-property stat)) 0))

(defun (setf character-stat-points) (value character stat)
  (let ((points (max 0 value)))
    (object-set-property character (stat-points-property stat) points)
    points))

;; ─── Levelling ──────────────────────────────────────────────────────────────

(defgeneric character-stat-level-up! (character stat)
  (:documentation
   "Apply STAT's side effects when CHARACTER gains a level in it.
STAT is a canonical keyword (see STAT-KEY).  The default does nothing;
specialize per stat — e.g. STAMINA raises maximum HP.")
  (:method (character stat)
    (declare (ignore character stat))
    nil)
  (:method (character (stat (eql :stamina)))
    ;; Maximum HP grew with the new stamina level: grant the character the
    ;; gained hit points, unless HP has not been initialized yet (then it
    ;; is filled lazily at the new maximum).
    (let ((hp (object-get-property character "hp")))
      (when hp
        (object-set-property character "hp" (+ hp +character-hp-per-stamina+))))))

(defgeneric character-stat-level-up-message (stat)
  (:documentation
   "Return the yellow message shown when a character's STAT grows.
Deliberately free of numbers — it conveys the *feeling* of progress.")
  (:method (stat)
    (declare (ignore stat))
    (yellow "A quiet sense of progress settles over you — you have grown, though you could not say by how much."))
  (:method ((stat (eql :stamina)))
    (yellow "Something deep within you settles and strengthens. Your breath comes easier, your stride sure and tireless; the road ahead no longer daunts you. (You have gained stamina)"))
  (:method ((stat (eql :intelligence)))
    (yellow "Your thoughts come quicker and clearer, and patterns that once hid in the noise now arrange themselves before you. (You have gained intelligence)")))

(defun character-gain-stat-points (character stat points)
  "Add POINTS toward CHARACTER's STAT, raising the level as thresholds are
reached — possibly more than once — and applying each level-up's effects
via CHARACTER-STAT-LEVEL-UP!.  Returns the number of levels gained."
  (let ((key (stat-key stat))
        (levels-gained 0))
    (loop
      (let ((level (character-stat character key)))
        (when (>= level +character-max-stat+)
          (return))
        (let* ((required (stat-points-to-advance level))
               (banked (+ (character-stat-points character key) points)))
          (if (>= banked required)
              (progn
                (setf (character-stat-points character key) (- banked required))
                (setf (character-stat character key) (1+ level))
                (character-stat-level-up! character key)
                (incf levels-gained)
                ;; The leftover is already banked; do not add POINTS twice.
                (setf points 0))
              (progn
                (setf (character-stat-points character key) banked)
                (return))))))
    levels-gained))

(defun character-award-stat-points (character stat points)
  "Award POINTS toward CHARACTER's STAT and, when a level is gained,
send the stat's yellow level-up message to the character.  This is the
shared entry point for every action that grows a stat.  Returns the
number of levels gained."
  (let* ((key (stat-key stat))
         (levels (character-gain-stat-points character key points)))
    (when (plusp levels)
      (character-send-message character (character-stat-level-up-message key)))
    levels))

;; ─── Named stats ────────────────────────────────────────────────────────────

(defun character-stamina (character)
  "Return CHARACTER's stamina level.  Stamina grows by walking."
  (character-stat character :stamina))

(defun (setf character-stamina) (value character)
  (setf (character-stat character :stamina) value))

(defun character-intelligence (character)
  "Return CHARACTER's intelligence level.  Intelligence grows by solving
Wordle puzzles."
  (character-stat character :intelligence))

(defun (setf character-intelligence) (value character)
  (setf (character-stat character :intelligence) value))

(defun character-stamina-points (character)
  "Points CHARACTER has banked toward the next stamina level."
  (character-stat-points character :stamina))

(defun character-intelligence-points (character)
  "Points CHARACTER has banked toward the next intelligence level."
  (character-stat-points character :intelligence))

(defun character-max-hp (character)
  "Return CHARACTER's maximum hit points, derived from stamina."
  (* +character-hp-per-stamina+ (character-stamina character)))

(defun character-hp (character)
  "Return CHARACTER's current hit points, defaulting lazily to maximum."
  (or (object-get-property character "hp") (character-max-hp character)))

(defun (setf character-hp) (value character)
  (let ((hp (max 0 value)))
    (object-set-property character "hp" hp)
    hp))

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
