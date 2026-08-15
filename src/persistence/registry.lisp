;;;; src/persistence/registry.lisp — Declarative persistent class registry
;;;;
;;;; DEFINE-PERSISTENT-CLASSES turns a serapeum dict mapping transient game
;;;; classes to options into the DEFWRAPPING-PERSISTENT-CLASS definitions,
;;;; and installs *PERSISTENT-CLASS-REGISTRY* so the transient → persistent
;;;; mapping is data, not class-hierarchy reflection.

(in-package :apeiron.persistence)

(defun unquote-symbol (form what)
  "Return FORM as a symbol, accepting a bare symbol or (QUOTE SYMBOL)."
  (cond ((symbolp form) form)
        ((and (consp form)
              (eq (first form) 'quote)
              (symbolp (second form))
              (null (cddr form)))
         (second form))
        (t (error "define-persistent-classes: ~A must be a symbol, got ~S"
                  what form))))

(defun parse-symbol-list-form (form what)
  "Parse FORM as a list of symbols for a list-valued registry option.
Accepts NIL, a quoted list (QUOTE (A B)), or a literal list form (A B)."
  (cond ((null form) nil)
        ((and (consp form) (eq (first form) 'quote) (listp (second form)))
         (second form))
        ((consp form)
         (mapcar (lambda (x) (unquote-symbol x what)) form))
        (t (error "define-persistent-classes: ~A must be a list of symbols, got ~S"
                  what form))))

(defun parse-persistent-class-options (form)
  "Parse an options dict form into an alist of (KEY . VALUE).
:TRANSIENT-SLOTS and :SUPERCLASSES become lists of symbols;
:PERSISTENT-NAME becomes a symbol."
  (cond ((null form) nil)
        ((and (consp form) (eq (first form) 'dict))
         (when (oddp (length (rest form)))
           (error "define-persistent-classes: odd number of forms in options dict ~S"
                  form))
         (loop for (key value) on (rest form) by #'cddr
               append
               (case key
                 (:transient-slots
                  (list (cons key (parse-symbol-list-form value ":transient-slots"))))
                 (:persistent-name
                  (list (cons key (unquote-symbol value ":persistent-name"))))
                 (:superclasses
                  (list (cons key (parse-symbol-list-form value ":superclasses"))))
                 (otherwise
                  (error "define-persistent-classes: unknown option ~S (supported: :transient-slots, :persistent-name, :superclasses)"
                         key)))))
        (t (error "define-persistent-classes: options must be a serapeum dict, got ~S"
                  form))))

(defun default-persistent-class-name (transient-name)
  "Derive the persistent class name for TRANSIENT-NAME.
MUD-ROOM → PERSISTENT-ROOM; HEAD → PERSISTENT-HEAD.
The result is interned in the current package (the macro call site)."
  (let* ((name (symbol-name transient-name))
         (pname (if (and (>= (length name) 4)
                         (string= name "MUD-" :end1 4))
                    (concatenate 'string "PERSISTENT-" (subseq name 4))
                    (concatenate 'string "PERSISTENT-" name))))
    (intern pname *package*)))

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
  (or (cdr (assoc :persistent-name options))
      (default-persistent-class-name transient-name)))

(defun persistent-superclasses (transient-name options)
  (or (cdr (assoc :superclasses options))
      (default-persistent-superclasses transient-name)))

(defun parse-persistent-registry-form (form)
  "Parse a serapeum dict form into an alist of (TRANSIENT-NAME . OPTIONS)."
  (unless (and (consp form) (eq (first form) 'dict))
    (error "define-persistent-classes: expected a serapeum dict, got ~S" form))
  (when (oddp (length (rest form)))
    (error "define-persistent-classes: odd number of forms in registry dict ~S"
           form))
  (loop for (key value) on (rest form) by #'cddr
        collect (cons (unquote-symbol key "registry key")
                      (parse-persistent-class-options value))))

(defun registry-value-form (transient-name options)
  "Build the runtime registry value form for one transient class."
  (let ((pname (persistent-class-name transient-name options))
        (supers (persistent-superclasses transient-name options))
        (slots (cdr (assoc :transient-slots options))))
    `(dict
      :persistent-class ',pname
      :superclasses ',supers
      ,@(when slots `(:transient-slots ',slots)))))

(defun class-definition-form (transient-name options)
  "Build the DEFWRAPPING-PERSISTENT-CLASS form for one transient class."
  (let ((pname (persistent-class-name transient-name options))
        (supers (persistent-superclasses transient-name options))
        (slots (cdr (assoc :transient-slots options))))
    `(defwrapping-persistent-class ,pname ,supers ()
       ,@(when slots `((:transient-slots ,@slots))))))

(defmacro define-persistent-classes (registry-form)
  "Declaratively register wrapping persistent classes for the MUD.

REGISTRY-FORM is a serapeum dict mapping each transient game class to an
options dict:

  (define-persistent-classes
    (dict
     'mud-object        (dict :transient-slots nil)
     'mud-room          (dict :transient-slots (contents))
     'mud-wordle-puzzle (dict :transient-slots (character-guesses)
                              :persistent-name persistent-wordle)))

For every entry a wrapping persistent class is defined:
  * name — PERSISTENT-<name> by default (MUD-ROOM → PERSISTENT-ROOM,
    HEAD → PERSISTENT-HEAD); override with :persistent-name.
  * superclasses — the transient class plus PERSISTENT-OBJECT when the
    transient class is a subtype of MUD-OBJECT (the common case);
    override with :superclasses.
  * transient slots — :transient-slots lists the slots inherited from
    the transient class that must NOT be stored in the datastore.
    Write the slot list as a literal list: (contents) or '(contents).

The macro also installs *PERSISTENT-CLASS-REGISTRY*, a serapeum dict
mapping each transient class name to its options plus the resolved
:persistent-class symbol, so TRANSIENT->PERSISTENT-CLASS can resolve
the persistent counterpart without walking the class hierarchy.

Entries are defined in the order given: list MUD-OBJECT (or any base
persistent class) before classes that inherit from it."
  (let ((entries (parse-persistent-registry-form registry-form)))
    `(progn
       (defparameter *persistent-class-registry*
         (dict ,@(loop for (transient-name . options) in entries
                       append (list `',transient-name
                                    (registry-value-form transient-name options)))))
       ,@(loop for (transient-name . options) in entries
               collect (class-definition-form transient-name options)))))
