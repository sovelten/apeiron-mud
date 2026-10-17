;;;; tests/core/test-verbs.lisp — Apeiron's verb sugar over CL-CM-DB
;;;;
;;;; The content-addressing properties (alpha equivalence, recursive
;;;; hashing, referrers, history, compiled-code pinning, ...) are tested in
;;;; CL-CM's own suite.  Here we test only what APEIRON.VERBS adds:
;;;;
;;;;   * DEFINE-VERB / REGISTER-VERB lambda-list + body sugar, including
;;;;     the docstring convention and :STRICT;
;;;;   * binding verbs on MUD objects by CID;
;;;;   * opening and persisting a world's verb database.

(in-package #:apeiron-test)

(in-suite core-suite)

(defvar *verb-test-database-counter* 0
  "Makes each test's verb database directory unique within an image.")

(defun fresh-verb-test-directory ()
  "A brand-new temporary directory for a test's verb database."
  (merge-pathnames
   (format nil "apeiron-verb-test-~D-~D/"
           (get-universal-time) (incf *verb-test-database-counter*))
   (uiop:temporary-directory)))

(defun fresh-verb-registry ()
  "A fresh verb database (a CL-CM-DB:CODE-DATABASE) in a temp directory."
  (cl-cm-db:ensure-database
   (cl-cm-db:make-database :directory (fresh-verb-test-directory)
                           :name "verbs")))

;;; ------------------------------------------------------------------
;;; Defining
;;; ------------------------------------------------------------------

(test define-verb-stores-a-lambda-identity
  "DEFINE-VERB turns a lambda list + body into a stored identity, runs
through the database's compiled function, and reports its docstring."
  (let ((reg (fresh-verb-registry)))
    (apeiron.verbs:define-verb reg add-one (x) "Adds one." (+ x 1))
    (is (stringp (cl-cm-db:identity-cid 'add-one reg)))
    (is (= 5 (cl-cm-db:call-identity 'add-one reg 4)))
    (is (equal '(lambda (x) "Adds one." (+ x 1))
               (cl-cm-db:identity-code 'add-one reg)))
    (is (equal "Adds one."
               (apeiron.verbs:verb-docstring
                (cl-cm-db:definition-by-identity 'add-one reg))))))

(test register-verb-strict-mode-signals
  "REGISTER-VERB with :STRICT signals when a reference cannot be resolved."
  (let ((reg (fresh-verb-registry)))
    (signals error
      (apeiron.verbs:register-verb reg 'bad '(x) '((undefined-helper x)) :strict t))
    ;; Without :STRICT the reference is merely recorded as unresolved.
    (apeiron.verbs:register-verb reg 'lenient '(x) '((undefined-helper x)))
    (multiple-value-bind (references unresolved)
        (cl-cm-db:code-references
         reg (cl-cm-db:identity-cid 'lenient reg))
      (declare (ignore references))
      (is (equal '(undefined-helper) unresolved)))))

;;; ------------------------------------------------------------------
;;; Integration with MUD objects
;;; ------------------------------------------------------------------

(test object-verb-binding-and-call
  "An object can carry a verb by CID and invoke it."
  (let ((reg (fresh-verb-registry))
        (obj (apeiron.core:new-object :name "crystal")))
    (apeiron.verbs:define-verb reg sparkle (n) (format nil "~D sparkles" n))
    (apeiron.verbs:object-define-verb! reg obj shine (n) (sparkle n))
    (is (equal '(shine) (apeiron.core:object-verb-names obj)))
    (is (stringp (apeiron.core:object-verb-cid obj 'shine)))
    (is (typep (apeiron.verbs:object-verb reg obj 'shine)
               'cl-cm-db:code-definition))
    (is (equal "3 sparkles" (apeiron.verbs:object-call-verb reg obj 'shine 3)))))

(test object-verb-share-and-pin
  "Two objects can share a definition by CID; redefining the callee moves
only the objects that are rebound, so the other stays pinned."
  (let ((reg (fresh-verb-registry))
        (a (apeiron.core:new-object :name "a"))
        (b (apeiron.core:new-object :name "b")))
    (apeiron.verbs:define-verb reg describe-it (x) (format nil "v1 ~A" x))
    (apeiron.verbs:object-define-verb! reg a show (x) (describe-it x))
    (apeiron.verbs:object-bind-verb! b 'show (apeiron.core:object-verb-cid a 'show))
    ;; Redefine the callee and rebind only A.
    (apeiron.verbs:define-verb reg describe-it (x) (format nil "v2 ~A" x))
    (apeiron.verbs:object-define-verb! reg a show (x) (describe-it x))
    (is (equal "v2 A" (apeiron.verbs:object-call-verb reg a 'show "A")))
    (is (equal "v1 B" (apeiron.verbs:object-call-verb reg b 'show "B"))
        "B was pinned to the older version")))

(test object-verb-remove
  "OBJECT-REMOVE-VERB unbinds a verb and returns its CID."
  (let ((reg (fresh-verb-registry))
        (obj (apeiron.core:new-object :name "thing")))
    (apeiron.verbs:object-define-verb! reg obj poke () :poked)
    (let ((cid (apeiron.core:object-verb-cid obj 'poke)))
      (is (equal cid (apeiron.core:object-remove-verb obj 'poke)))
      (is (null (apeiron.core:object-verb-cid obj 'poke)))
      (is (null (apeiron.core:object-verb-names obj)))
      (signals error (apeiron.verbs:object-call-verb reg obj 'poke)))))

(test object-verbs-slot-defaults-empty
  "A freshly created object carries an empty verb map (so an old datastore
gains one via the transient-instance initform)."
  (let ((obj (apeiron.core:new-object :name "fresh")))
    (is (typep (apeiron.core:object-verbs obj) 'fset:map))
    (is (fset:empty? (apeiron.core:object-verbs obj)))))

;;; ------------------------------------------------------------------
;;; A world's database
;;; ------------------------------------------------------------------

(test world-verb-registry-is-lazy
  "A world's verb database is created on first use and reused after."
  (let ((world (make-instance 'mud-world))
        (directory (fresh-verb-test-directory)))
    (is (null (apeiron.core:world-verb-registry world)))
    (let ((reg (apeiron.verbs:ensure-verb-registry world :directory directory)))
      (is (typep reg 'cl-cm-db:code-database))
      (is (eq reg (apeiron.verbs:ensure-verb-registry world :directory directory))))))

(test world-verb-registry-persists-in-code-database
  "A world's registry is backed by an on-disk CL-CM-DB database, so
dropping the transient registry and re-opening it preserves CIDs and
per-object bindings."
  (let ((world (make-instance 'mud-world))
        (obj (apeiron.core:new-object :name "widget"))
        (directory (fresh-verb-test-directory)))
    (apeiron.verbs:object-define-verb! (apeiron.verbs:ensure-verb-registry
                                        world :directory directory)
                                       obj whirr ()
                                       "Whirr."
                                       (format nil "whirr"))
    ;; Simulate a restart: drop the transient registry, then reopen the db.
    (setf (apeiron.core:world-verb-registry world) nil)
    (is (null (apeiron.core:world-verb-registry world)))
    (let ((reg (apeiron.verbs:ensure-verb-registry world :directory directory)))
      (is (typep reg 'cl-cm-db:code-database))
      (is (equal "whirr" (apeiron.verbs:object-call-verb reg obj 'whirr)))
      (is (equal "Whirr."
                 (apeiron.verbs:verb-docstring
                  (apeiron.verbs:object-verb reg obj 'whirr))))
      (is (string= (apeiron.core:object-verb-cid obj 'whirr)
                   (cl-cm-db:identity-cid 'whirr reg))))))
