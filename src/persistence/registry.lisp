;;;; src/persistence/registry.lisp — Declarative persistent class registry
;;;;
;;;; *PERSISTENT-CLASS-REGISTRY* is plain data — a serapeum dict mapping
;;;; each transient game class to options for its wrapping persistent
;;;; class.  DEFINE-PERSISTENT-CLASSES (a function, no macro) reads that
;;;; data at load time and defines the PERSISTENT-* classes, so the
;;;; transient → persistent mapping lives in data, not in code.

(in-package :apeiron.persistence)

(defun default-persistent-class-name (transient-name)
  "Derive the persistent class name for TRANSIENT-NAME.
MUD-ROOM → PERSISTENT-ROOM; LIMB → PERSISTENT-LIMB.
The result is interned in the APEIRON.PERSISTENCE package, where the
persistent classes live."
  (let* ((name (symbol-name transient-name))
         (pname (if (and (>= (length name) 4)
                         (string= name "MUD-" :end1 4))
                    (concatenate 'string "PERSISTENT-" (subseq name 4))
                    (concatenate 'string "PERSISTENT-" name))))
    (intern pname (find-package :apeiron.persistence))))

(defun default-persistent-superclasses (transient-name)
  "Superclasses for the persistent wrapper of TRANSIENT-NAME: the
transient class itself, plus PERSISTENT-OBJECT when it is a game object
(a subtype of MUD-OBJECT other than MUD-OBJECT itself)."
  (if (and (find-class 'mud-object nil)
           (not (eq transient-name 'mud-object))
           (subtypep transient-name 'mud-object))
      (list transient-name 'persistent-object)
      (list transient-name)))

(defun persistent-class-name (transient-name options)
  "Persistent class name for TRANSIENT-NAME: the :PERSISTENT-NAME option
or the derived PERSISTENT-<name>."
  (or (gethash :persistent-name options)
      (default-persistent-class-name transient-name)))

(defun persistent-superclasses (transient-name options)
  "Superclass list for the persistent wrapper of TRANSIENT-NAME: the
:SUPERCLASSES option or the derived default."
  (or (gethash :superclasses options)
      (default-persistent-superclasses transient-name)))

(defun persistent-class-entry-p (name registry)
  "True if NAME is the persistent class of some entry in REGISTRY
(as derived from each entry's options by PERSISTENT-CLASS-NAME)."
  (let ((found nil))
    (maphash (lambda (transient-name options)
               (when (eq name (persistent-class-name transient-name options))
                 (setf found t)))
             registry)
    found))

(defun define-persistent-class (transient-name options)
  "Define the wrapping persistent class for TRANSIENT-NAME with OPTIONS.

STORE-OBJECT is appended to the superclasses so the class participates
in the BKNR datastore; the WRAPPING-PERSISTENT-CLASS metaclass turns the
:TRANSIENT-SLOTS option into transient (non-persisted) slot definitions."
  (let ((pname (persistent-class-name transient-name options))
        (supers (persistent-superclasses transient-name options))
        (slots (gethash :transient-slots options)))
    (sb-mop:ensure-class pname
                         :metaclass 'wrapping-persistent-class
                         :direct-superclasses
                         (mapcar #'find-class
                                 (append supers '(bknr.datastore:store-object)))
                         :direct-slots nil
                         :transient-slots (or slots nil))))

(defun define-persistent-classes (registry)
  "Define the wrapping persistent classes declared in REGISTRY.

REGISTRY is a serapeum dict mapping each transient game class name to an
options dict:

  (dict 'mud-room (dict :transient-slots '(contents)))

Supported options:
  :transient-slots — list of slot names inherited from the transient
                     class that must NOT be stored in the datastore.
  :persistent-name — symbol for the persistent class; defaults to
                     PERSISTENT-<name> (MUD-ROOM → PERSISTENT-ROOM).
  :superclasses    — explicit superclass list; defaults to the transient
                     class plus PERSISTENT-OBJECT when the transient
                     class is a subtype of MUD-OBJECT (the common case).

Entries may be listed in any order: dependencies between persistent
classes (e.g. on PERSISTENT-OBJECT) are resolved automatically."
  (let ((remaining nil)
        (defined nil))
    (maphash (lambda (name options)
               (push (cons name options) remaining))
             registry)
    (loop while remaining
          do (let ((ready (remove-if-not
                           (lambda (entry)
                             (every (lambda (super)
                                      (or (not (persistent-class-entry-p super registry))
                                          (member super defined :test #'eq)))
                                    (persistent-superclasses (car entry) (cdr entry))))
                           remaining)))
               (when (null ready)
                 (error "define-persistent-classes: cannot resolve class dependencies for: ~S"
                        (mapcar #'car remaining)))
               (dolist (entry ready)
                 (define-persistent-class (car entry) (cdr entry))
                 (push (persistent-class-name (car entry) (cdr entry)) defined)
                 (setf remaining (remove entry remaining :test #'eq))))))
  (values))

(defparameter *persistent-class-registry*
  (dict
   'mud-object        (dict)
   ;; properties is intentionally NOT transient — objects store meaningful
   ;; game state via object-set-property that must survive restarts.
   'mud-room          (dict :transient-slots '(contents))
   'mud-character     (dict :transient-slots '(session))
   'limb              (dict)
   'mud-guestbook     (dict :transient-slots '(entries))
   'mud-npc           (dict)
   'mud-wordle-puzzle (dict :transient-slots '(character-guesses)
                            :persistent-name 'persistent-wordle)
   'mud-connection    (dict)
   'mud-area          (dict :transient-slots '(graph))
   ;; the cl-graph index is derived from rooms/connections and rebuilt on
   ;; restore (see INITIALIZE-TRANSIENT-INSTANCE in persistent-world.lisp).
   'mud-world         (dict :transient-slots '(characters objects rooms areas parser)))
  "Declarative registry of persistent classes: a serapeum dict mapping
each transient game class name to an options dict (see
DEFINE-PERSISTENT-CLASSES).")

(define-persistent-classes *persistent-class-registry*)
