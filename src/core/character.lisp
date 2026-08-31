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
   (owner :initarg :owner
          :accessor character-owner
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

(defun new-character (name session &key owner)
  (let ((character (make-instance 'mud-character
                                  :name name
                                  :session session
                                  :owner owner)))
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
Guest characters (no owner) are never administrators."
  (let ((owner (character-owner character)))
    (and owner
         (let ((account (find-account owner)))
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
  (null (character-owner character)))
