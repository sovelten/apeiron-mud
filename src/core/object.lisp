(in-package #:apeiron.core)

(defclass mud-object ()
  ((id :initarg :id
       :initform -1 ;; Set id when added to world
       :accessor object-id
       :documentation "Unique identifier for this object")
   (name :initarg :name
         :accessor object-name
         :initform "unnamed object"
         :documentation "Display name of the object")
   (description :initarg :description
                :accessor object-description
                :initform ""
                :documentation "Object description")
   (location :initarg :location
             :accessor object-location
             :initform nil
             :documentation "Location/container of this object")
   (aliases :initarg :aliases
            :accessor object-aliases
            :initform nil
            :documentation "List of alternative name strings for matching")
   (keywords :initarg :keywords
             :accessor object-keywords
             :initform nil
             :documentation "List of keywords representing the object")
   (properties :initarg :properties
               :accessor object-properties
               :initform (make-hash-table :test #'equal)
               :documentation "Extensible property storage"))
  (:documentation "Base class for all MUD objects"))

(defgeneric object-describe (obj)
  (:documentation
   "Get a description of an object with type-based ANSI coloring.
Specialized methods on subclasses provide appropriate coloring."))

(defgeneric object-set-property (obj property-name value)
  (:documentation
   "Set a property value on an object.

The default method modifies the hash-table in-place.

Specialized methods on persistent objects should also ensure the slot
is written so BKNR's transaction logging captures the change."))

(defun new-object (&key (name "object") (location nil)
                        (description "") (aliases nil) (keywords nil))
  "Create a new MUD object.  KEYWORDS control which body slots the object
can be worn/held in (see WEAR and ITEM-FITS-SLOT-P)."
  (make-instance 'mud-object
                 :name name
                 :location location
                 :description description
                 :aliases aliases
                 :keywords keywords))

(defun object-name-matches (obj name)
  "Return non-NIL if NAME matches the object's primary name (exact or whole-word,
case-insensitive) or any alias (exact, case-insensitive). Returns NIL for empty NAME."
  (and (plusp (length name))
       (or (string-equal name (object-name obj))
           (let ((name-down (string-downcase name))
                 (words (str:words (object-name obj))))
             (some (lambda (word) (string-equal name-down word)) words))
           (some (lambda (alias) (string-equal name alias))
                 (object-aliases obj)))))

(defun object-get-property (obj property-name)
  "Get a property value from an object."
  (gethash property-name (object-properties obj)))

(defmethod object-set-property (obj property-name value)
  "Default: modify the properties hash-table in-place."
  (setf (gethash property-name (object-properties obj)) value))

(defun object-move (obj new-location)
  "Move an object to a new location."
  (let ((old-location (object-location obj)))
    ;; Remove from old location if it's a room
    (when (and old-location (typep old-location 'mud-room))
      (container-remove-object old-location obj))
    ;; Set new location
    (setf (object-location obj) new-location)
    ;; Add to new location if it's a room
    (when (typep new-location 'mud-room)
      (container-add-object new-location obj))
    t))

(defmethod object-describe ((obj mud-object))
  "Default: no color."
  (format nil "~A (ID: ~D)" (object-name obj) (object-id obj)))

;; Print object in REPL with useful information
(defmethod print-object ((obj mud-object) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~A (ID: ~D)"
            (object-name obj)
            (object-id obj))))


;; ─── Command processing handling ──────────────────────────────────────────────────────
;; Responses to commands that objects can implement.
;; By convention, for tell command, use handle-tell etc.
;; Command-handler should call appropriate handler if eligible.

(defgeneric handle-tell (object speaker message)
  (:documentation "Called when SPEAKER directs MESSAGE at OBJECT.
  Returns non-NIL if the speech was handled, NIL otherwise.")
  (:method (object speaker message)
    (declare (ignore object speaker message))
    nil))

(defgeneric handle-read (object reader)
  (:documentation "Called when READER tries to read OBJECT.
  Should display the readable content to the reader and return non-NIL.
  Returns NIL if the object has nothing readable.")
  (:method (object reader)
    (declare (ignore object reader))
    nil))

(defgeneric handle-write (object writer message)
  (:documentation "Called when WRITER tries to write MESSAGE on OBJECT.
  Should record the message and return non-NIL.
  Returns NIL if the object is not writable.")
  (:method (object writer message)
    (declare (ignore object writer message))
    nil))

(defgeneric handle-hold (object writer)
  (:documentation "Called when WRITER holds OBJECT in a hand.
  Should record the message and return non-NIL.
  Returns NIL if the object has nothing to say.")
  (:method (object writer)
    (declare (ignore object writer))
    nil))

(defgeneric handle-wear (object writer)
  (:documentation "Called when WRITER wears OBJECT on their body (e.g. a hat
on the head).  Should record the message and return non-NIL.
  Returns NIL if the object has nothing to say.")
  (:method (object writer)
    (declare (ignore object writer))
    nil))
