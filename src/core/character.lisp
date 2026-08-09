(in-package #:apeiron.core)

;; TODO: split character and player-character for building NPCs

(defun default-character-limbs ()
  "Return the standard set of limbs for a humanoid character: a head, a
left hand, and a right hand."
  (list (make-head :name "head")
        (make-hand :name "left hand")
        (make-hand :name "right hand")))

(defclass mud-character (mud-object container-mixin)
  ((session :initarg :session
            :accessor character-session
            :initform nil
            :documentation "The session controlling this character")
   (limbs :initarg :limbs
          :accessor character-limbs
          :initform (default-character-limbs)
          :documentation "The character limbs (hands, head(s) etc.), a list
of ITEM-SLOT-MIXIN objects (see HUMAN).  Each limb's ITEM slot holds what
is currently worn/held there.  On persistent characters the limbs are
materialized into the datastore so their ITEM slots persist.")
   (owner :initarg :owner
          :accessor character-owner
          :initform nil
          :documentation "The name (string) of the mud-account that owns this character.
NIL for guest characters.  Stored as a plain string so it survives
BKNR restarts without needing an object reference."))
  (:documentation "A character in the MUD"))

(defgeneric wear (character object &optional limb)
  (:documentation "Equip OBJECT on CHARACTER.
LIMB may be an ITEM-SLOT-MIXIN, a limb name string (e.g. \"head\",
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
  (find-if (lambda (limb) (string-equal (item-slot-name limb) name))
           (character-limbs character)))

(defun find-limb-holding (character object)
  "Return the limb of CHARACTER currently holding OBJECT, or NIL."
  (find-if (lambda (limb) (eq (item-slot limb) object))
           (character-limbs character)))

(defun find-fitting-limb (character object)
  "Return the first limb of CHARACTER whose keywords fit OBJECT (whether
or not it is already occupied), or NIL."
  (find-if (lambda (limb) (item-fits-slot-p object limb))
           (character-limbs character)))

(defun character-worn-items (character)
  "Return an alist of (LIMB . ITEM) for every item currently worn or held,
in limb order."
  (loop for limb in (character-limbs character)
        for item = (item-slot limb)
        when item
          collect (cons limb item)))

(defmethod wear ((character mud-character) object &optional limb)
  "Equip OBJECT on CHARACTER — see the WEAR generic documentation."
  (let* ((requested-name (when (stringp limb) limb))
         (target (cond
                   ((typep limb 'item-slot-mixin) limb)
                   (requested-name (find-limb-by-name character requested-name))
                   (t (find-fitting-limb character object)))))
    (cond
      ((null target)
       (values nil (if requested-name :no-such-limb :no-fitting-limb)))
      ((not (item-fits-slot-p object target))
       (values target :keywords-dont-match))
      ((not (item-slot-empty-p target))
       (values target :occupied))
      ((not (member object (container-all-objects character) :test #'eq))
       (values nil :not-in-inventory))
      (t
       (container-remove-object character object)
       (setf (item-slot target) object)
       (setf (object-location object) character)
       (values target :ok)))))

(defmethod unequip ((character mud-character) object)
  "Remove OBJECT from its limb and return it to inventory — see UNEQUIP."
  (let ((limb (find-limb-holding character object)))
    (if limb
        (progn
          (setf (item-slot limb) nil)
          (container-add-object character object)
          (values object limb))
        (values nil nil))))

(defmethod object-describe ((obj mud-character))
  "Bright green for character characters, listing any worn/held items."
  (let ((base (bright-green (format nil "~A (ID: ~D)"
                                    (object-name obj) (object-id obj))))
        (worn (character-worn-items obj)))
    (if worn
        (format nil "~A~%~A~{~A~^~%~}"
                base
                (bold-white "Wearing/holding:")
                (mapcar (lambda (pair)
                          (format nil "  - ~A (~A)"
                                  (object-describe (cdr pair))
                                  (item-slot-name (car pair))))
                        worn))
        base)))

(defun guest? (character)
  (null (character-owner character)))
