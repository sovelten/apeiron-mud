;;;; tests/core/test-verbs.lisp — content-addressed verb registry (APEIRON/VERBS)
;;;;
;;;; These tests pin down the properties that make the registry *content
;;;; addressed* rather than name based:
;;;;
;;;;   * the CID of a verb does not depend on the names of its own bound
;;;;     variables (alpha equivalence) nor on the name it is registered
;;;;     under;
;;;;   * the CID DOES depend on the CIDs of the verbs it references, so
;;;;     editing a callee changes the caller's CID (recursive content
;;;;     addressing) while merely renaming anything changes nothing;
;;;;   * identical verbs are stored once (deduplication);
;;;;   * a compiled caller keeps reaching the version it was compiled
;;;;     against, even after the callee is redefined under the same name.
;;;;
;;;; The registry and the per-object bindings are also exercised end to end
;;;; through CALL-VERB / OBJECT-CALL-VERB and through a serialization
;;;; round-trip.

(in-package #:apeiron-test)

(in-suite core-suite)

;;; ------------------------------------------------------------------
;;; Defining and calling
;;; ------------------------------------------------------------------

(test verb-define-and-call
  "A verb can be defined, addressed by name and by CID, and called."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg add-one (x) (+ x 1))
    (is (= 1 (apeiron.verbs:verb-count reg)))
    (is (stringp (apeiron.verbs:verb-cid reg 'add-one)))
    (is (string= (apeiron.verbs:verb-cid reg 'add-one)
                 (apeiron.verbs:verb-cid reg (apeiron.verbs:verb-cid reg 'add-one)))
        "a verb is addressable by its CID as well as by name")
    (is (= 5 (apeiron.verbs:call-verb reg 'add-one 4)))
    (is (eq 'add-one (apeiron.verbs:verb-definition-name
                      (apeiron.verbs:find-verb reg 'add-one))))))

(test verb-docstring-is-part-of-the-content
  "A leading string is a docstring, reported by VERB-DOCSTRING.  Being
content, it participates in the CID, so a verb can be re-documented and
identical code-plus-docstring deduplicates."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg one-a (x) "Adds one." (+ x 1))
    (is (equal "Adds one." (apeiron.verbs:verb-docstring reg 'one-a)))
    ;; Same code with no docstring is a different definition.
    (apeiron.verbs:define-verb reg one-b (x) (+ x 1))
    (is (not (string= (apeiron.verbs:verb-cid reg 'one-a)
                      (apeiron.verbs:verb-cid reg 'one-b))))
    ;; Identical code AND docstring deduplicate.
    (apeiron.verbs:define-verb reg one-c (x) "Adds one." (+ x 1))
    (is (string= (apeiron.verbs:verb-cid reg 'one-a)
                 (apeiron.verbs:verb-cid reg 'one-c)))
    ;; Re-documenting a name re-binds it to a new definition.
    (let ((before (apeiron.verbs:verb-cid reg 'one-a)))
      (apeiron.verbs:define-verb reg one-a (x) "Adds 1." (+ x 1))
      (is (not (string= before (apeiron.verbs:verb-cid reg 'one-a))))
      (is (equal "Adds 1." (apeiron.verbs:verb-docstring reg 'one-a))))))

;;; ------------------------------------------------------------------
;;; Alpha equivalence and renaming independence
;;; ------------------------------------------------------------------

(test verb-cid-alpha-invariant
  "Renaming a verb's own bound variables does not change its CID."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg f1 (x) (+ x 1))
    (apeiron.verbs:define-verb reg f2 (y) (+ y 1))
    (is (string= (apeiron.verbs:verb-cid reg 'f1)
                 (apeiron.verbs:verb-cid reg 'f2)))
    (is (= 1 (apeiron.verbs:verb-count reg))
        "identical code is stored once, however it is named")))

(test verb-cid-name-independent
  "The name a verb is registered under is not part of its CID."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg alpha (x) (* x x))
    (let ((cid (apeiron.verbs:verb-cid reg 'alpha)))
      (apeiron.verbs:define-verb reg beta (x) (* x x))
      (is (string= cid (apeiron.verbs:verb-cid reg 'beta)))
      (is (equal '(alpha beta)
                 (sort (apeiron.verbs:verb-names reg cid) #'string< :key #'symbol-name))
          "both names resolve to the same definition"))))

;;; ------------------------------------------------------------------
;;; Recursive content addressing
;;; ------------------------------------------------------------------

(test verb-cid-recursive-hashing
  "A caller's CID depends on the CID of the verb it calls (recursive
content addressing), so editing a callee changes the caller's CID."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg callee (x) (+ x 1))
    (apeiron.verbs:define-verb reg caller (x) (callee (callee x)))
    (let ((callee-v1 (apeiron.verbs:verb-cid reg 'callee))
          (caller-v1 (apeiron.verbs:verb-cid reg 'caller)))
      (is (equal (list (cons 'callee callee-v1))
                 (apeiron.verbs:verb-references reg 'caller))
          "the caller records a reference to the callee's CID")
      ;; Edit the callee; both CIDs must change.
      (apeiron.verbs:define-verb reg callee (x) (+ x 2))
      (apeiron.verbs:define-verb reg caller (x) (callee (callee x)))
      (is (not (string= callee-v1 (apeiron.verbs:verb-cid reg 'callee))))
      (is (not (string= caller-v1 (apeiron.verbs:verb-cid reg 'caller)))
          "editing the callee gives the caller a new CID"))))

(test verb-cid-rename-of-callee-is-invisible
  "Renaming a callee does not change a caller's CID: the reference is to
the callee's CID, not to its name."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg callee (x) (+ x 1))
    (apeiron.verbs:define-verb reg caller (x) (callee x))
    (let ((caller-cid (apeiron.verbs:verb-cid reg 'caller)))
      ;; Give the *same* definition a second name; the caller still refers
      ;; to the same CID, so re-registering the caller is a no-op.
      (apeiron.verbs:define-verb reg alias (x) (+ x 1))
      (apeiron.verbs:define-verb reg caller (x) (alias x))
      (is (string= caller-cid (apeiron.verbs:verb-cid reg 'caller))))))

;;; ------------------------------------------------------------------
;;; History and referrers
;;; ------------------------------------------------------------------

(test verb-history-newest-first
  "HISTORY records every CID a name has been bound to, newest first."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg v (x) (+ x 1))
    (let ((v1 (apeiron.verbs:verb-cid reg 'v)))
      (apeiron.verbs:define-verb reg v (x) (+ x 2))
      (let ((v2 (apeiron.verbs:verb-cid reg 'v)))
        (is (not (string= v1 v2)))
        (is (equal (list v2 v1) (apeiron.verbs:verb-history reg 'v))
            "newest binding first")))))

(test verb-referrers-are-naming-independent
  "REFERRERS returns the names whose *current* definition references a
given CID, and is unaffected by renaming the referrer."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg base (x) (+ x 1))
    (apeiron.verbs:define-verb reg uses-base (x) (base x))
    (is (equal '(uses-base) (apeiron.verbs:verb-referrers reg 'base)))
    ;; Rename the referrer: same code, different name, same answer.
    (apeiron.verbs:define-verb reg also-uses (x) (base x))
    (is (equal '(also-uses uses-base)
               (apeiron.verbs:verb-referrers reg 'base)))
    ;; A verb nobody references has no referrers.
    (is (null (apeiron.verbs:verb-referrers reg 'uses-base)))))

;;; ------------------------------------------------------------------
;;; Unresolved references and strict mode
;;; ------------------------------------------------------------------

(test verb-unresolved-references
  "Free functions that are not registered verbs are recorded as unresolved."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg shout (x) (format nil "~A!" x))
    (is (equal '(format) (apeiron.verbs:verb-unresolved-references reg 'shout)))
    (is (null (apeiron.verbs:verb-references reg 'shout)))
    (is (equal "hi!" (apeiron.verbs:call-verb reg 'shout "hi")))))

(test verb-strict-mode-signals
  "REGISTER-VERB with :STRICT signals when a reference cannot be resolved."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (signals error
      (apeiron.verbs:register-verb reg 'bad '(x) '((undefined-helper x)) :strict t))
    ;; Without :STRICT the reference is merely recorded as unresolved.
    (apeiron.verbs:register-verb reg 'lenient '(x) '((undefined-helper x)))
    (is (equal '(undefined-helper)
               (apeiron.verbs:verb-unresolved-references reg 'lenient)))))

;;; ------------------------------------------------------------------
;;; Nested invocation
;;; ------------------------------------------------------------------

(test verb-call-verb-nests-references
  "CALL-VERB runs a verb whose body calls another verb."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg double (x) (* x 2))
    (apeiron.verbs:define-verb reg quadruple (x) (double (double x)))
    (is (= 24 (apeiron.verbs:call-verb reg 'quadruple 6)))))

(test verb-call-verb-pins-version
  "A compiled caller reaches the version of the callee it was compiled
against, even after the callee is redefined under the same name."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg inc (x) (+ x 1))
    (apeiron.verbs:define-verb reg twice (x) (inc (inc x)))
    (is (= 12 (apeiron.verbs:call-verb reg 'twice 10)))
    ;; Redefine INC to add 10.  The already-compiled TWICE still uses +1.
    (apeiron.verbs:define-verb reg inc (x) (+ x 10))
    (is (= 12 (apeiron.verbs:call-verb reg 'twice 10))
        "TWICE still points at the version of INC it was built from")
    ;; A freshly defined caller picks up the new INC.
    (apeiron.verbs:define-verb reg twice (x) (inc (inc x)))
    (is (= 30 (apeiron.verbs:call-verb reg 'twice 10)))))

(test verb-name-may-be-a-cl-symbol
  "A verb may be named by a symbol of a locked package (e.g. CL:GET or
CL:REMOVE); pinning such a reference must not violate the package lock."
  (let ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg get (k) (list :got k))
    (apeiron.verbs:define-verb reg remove (x) (get x))
    (is (eq 'get 'cl:get) "sanity: GET here is the CL symbol")
    (is (equal '(:got 7) (apeiron.verbs:call-verb reg 'remove 7)))
    (is (equal '(remove) (apeiron.verbs:verb-referrers reg 'get)))))

;;; ------------------------------------------------------------------
;;; Registry as a value: MAP-VERBS and serialization
;;; ------------------------------------------------------------------

(test verb-map-verbs-visits-every-definition
  "MAP-VERBS calls its function once per distinct definition."
  (let ((reg (apeiron.verbs:make-verb-registry))
        (seen '()))
    (apeiron.verbs:define-verb reg one (x) (+ x 1))
    (apeiron.verbs:define-verb reg two (x) (+ x 2))
    (apeiron.verbs:map-verbs (lambda (def) (push (apeiron.verbs:verb-definition-cid def) seen)) reg)
    (is (= 2 (length seen)))
    (is (equal (sort seen #'string<)
               (sort (list (apeiron.verbs:verb-cid reg 'one)
                           (apeiron.verbs:verb-cid reg 'two))
                     #'string<)))))

(test verb-registry-serialization-round-trip
  "VERB-REGISTRY->MAP / MAP->VERB-REGISTRY preserve CIDs, names, history
and callability without re-hashing."
  (let* ((reg (apeiron.verbs:make-verb-registry)))
    (apeiron.verbs:define-verb reg add-one (x) "Adds one." (+ x 1))
    (apeiron.verbs:define-verb reg twice (x) (add-one (add-one x)))
    (apeiron.verbs:define-verb reg twice (x) (add-one (add-one (add-one x))))
    (let* ((map (apeiron.verbs:verb-registry->map reg))
           (restored (apeiron.verbs:map->verb-registry map)))
      (is (= (apeiron.verbs:verb-count reg) (apeiron.verbs:verb-count restored)))
      (is (string= (apeiron.verbs:verb-cid reg 'twice)
                   (apeiron.verbs:verb-cid restored 'twice))
          "CIDs are restored verbatim")
      (is (equal (apeiron.verbs:verb-history reg 'twice)
                 (apeiron.verbs:verb-history restored 'twice)))
      (is (equal (apeiron.verbs:verb-docstring restored 'add-one) "Adds one."))
      (is (equal (apeiron.verbs:verb-references restored 'twice)
                 (apeiron.verbs:verb-references reg 'twice)))
      (is (= 13 (apeiron.verbs:call-verb restored 'twice 10))
          "the restored verb still runs"))))

;;; ------------------------------------------------------------------
;;; Integration with MUD objects
;;; ------------------------------------------------------------------

(test object-verb-binding-and-call
  "An object can carry a verb by CID and invoke it."
  (let ((reg (apeiron.verbs:make-verb-registry))
        (obj (apeiron.core:new-object :name "crystal")))
    (apeiron.verbs:define-verb reg sparkle (n) (format nil "~D sparkles" n))
    (apeiron.verbs:object-define-verb! reg obj shine (n) (sparkle n))
    (is (equal '(shine) (apeiron.core:object-verb-names obj)))
    (is (stringp (apeiron.core:object-verb-cid obj 'shine)))
    (is (typep (apeiron.verbs:object-verb reg obj 'shine)
               'apeiron.verbs:verb-definition))
    (is (equal "3 sparkles" (apeiron.verbs:object-call-verb reg obj 'shine 3)))))

(test object-verb-share-and-pin
  "Two objects can share a definition by CID; redefining the callee moves
only the objects that are rebound, so the other stays pinned."
  (let ((reg (apeiron.verbs:make-verb-registry))
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
  (let ((reg (apeiron.verbs:make-verb-registry))
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

(test world-verb-registry-is-lazy
  "A world's verb registry is created on first use and reused after."
  (let ((world (make-instance 'mud-world)))
    (is (null (apeiron.core:world-verb-registry world)))
    (let ((reg (apeiron.verbs:ensure-verb-registry world)))
      (is (typep reg 'apeiron.verbs:verb-registry))
      (is (eq reg (apeiron.verbs:ensure-verb-registry world))))))

(test world-verb-registry-save-and-load
  "SAVE-VERB-REGISTRY! / LOAD-VERB-REGISTRY! round-trip a world's registry
through its CONFIG map, preserving CIDs and per-object bindings."
  (let ((world (make-instance 'mud-world))
        (obj (apeiron.core:new-object :name "widget")))
    (apeiron.verbs:object-define-verb! (apeiron.verbs:ensure-verb-registry world)
                                       obj whirr ()
                                       "Whirr."
                                       (format nil "whirr"))
    (apeiron.verbs:save-verb-registry! world)
    ;; Simulate a restart: drop the transient registry, then reload it.
    (setf (apeiron.core:world-verb-registry world) nil)
    (is (null (apeiron.core:world-verb-registry world)))
    (let ((reg (apeiron.verbs:load-verb-registry! world)))
      (is (typep reg 'apeiron.verbs:verb-registry))
      (is (equal "whirr" (apeiron.verbs:object-call-verb reg obj 'whirr)))
      (is (equal "Whirr." (apeiron.verbs:verb-docstring reg 'whirr))))))
