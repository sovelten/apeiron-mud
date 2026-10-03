;;;; src/verbs/registry.lisp — the content-addressed verb registry
;;;;
;;;; A verb is defined by its SOURCE (a `(lambda LAMBDA-LIST . BODY)' form),
;;;; from which CL-CM computes a CID.  Before hashing, every FREE function
;;;; reference is resolved, through CL-CM's *REFERENCE-RESOLVER*, to the CID
;;;; of the verb currently bound to that name.  Two consequences:
;;;;
;;;;   * the CID does not depend on the names of the verb's own bound
;;;;     variables (alpha-equivalence), nor on the name it is registered
;;;;     under; and
;;;;   * the CID of a verb DOES depend on the CIDs of the verbs it calls, so
;;;;     editing a callee changes the caller's CID (recursive content
;;;;     addressing).
;;;;
;;;; A leading string in the body is the verb's docstring (DEFUN
;;;; convention), reported by VERB-DOCSTRING.  It is *content*: it stays in
;;;; the body and takes part in the CID, so re-documenting a verb produces
;;;; a new definition.
;;;;
;;;; The registry keeps three immutable FSET maps (so it is a value that can
;;;; be swapped into a slot and persisted — see SERIALIZE):
;;;;   DEFINITIONS  cid  -> VERB-DEFINITION
;;;;   NAMES        name -> cid      (the current binding of a name)
;;;;   HISTORY      name -> (cid cid ...)  (newest first)
;;;; plus a transient hash table mapping cid -> compiled function.

(in-package #:apeiron.verbs)

;;; ------------------------------------------------------------------
;;; Definitions
;;; ------------------------------------------------------------------

(defclass verb-definition ()
  ((cid :initarg :cid :reader verb-definition-cid)
   (name :initarg :name :reader verb-definition-name)
   (lambda-list :initarg :lambda-list :reader verb-definition-lambda-list)
   (body :initarg :body :reader verb-definition-body)
   (source :initarg :source :reader verb-definition-source)
   (docstring :initarg :docstring :initform nil :reader verb-definition-docstring
              :documentation "The verb's docstring (its BODY's leading
string literal, as in DEFUN), or NIL.  It stays in the body and is thus
part of the CID: the documentation is content.")
   (references :initarg :references :initform nil
               :reader verb-definition-references
               :documentation "Alist (SYMBOL . CID) of free function
references that were resolved to a CID, sorted by symbol name.")
   (unresolved-references :initarg :unresolved-references :initform nil
                          :reader verb-definition-unresolved-references
                          :documentation "Free function symbols that were NOT
resolved to a verb CID (they will be looked up as ordinary functions at
call time).")
   (created-at :initarg :created-at :initform 0 :reader verb-definition-created-at))
  (:documentation "A stored verb: its identity (CID), the name it was
registered under, its source, and the references it resolved."))

(defmethod print-object ((def verb-definition) stream)
  (print-unreadable-object (def stream :type t)
    (format stream "~A ~A" (verb-definition-name def) (verb-definition-cid def))))

;;; ------------------------------------------------------------------
;;; The registry
;;; ------------------------------------------------------------------

(defclass verb-registry ()
  ((definitions :initform (fset:empty-map) :accessor registry-definitions)
   (names :initform (fset:empty-map) :accessor registry-names)
   (history :initform (fset:empty-map) :accessor registry-history)
   (functions :initform (make-hash-table :test #'equal)
              :accessor registry-functions
              :documentation "Transient cache: cid -> compiled function."))
  (:documentation "A content-addressed store of verbs.  See the file
header for the shape of the three persistent maps."))

(defmethod print-object ((reg verb-registry) stream)
  (print-unreadable-object (reg stream :type t)
    (format stream "~D verb~:P" (verb-count reg))))

(defun make-verb-registry ()
  "Return a new, empty verb registry."
  (make-instance 'verb-registry))

(defun verb-count (registry)
  "Number of distinct definitions (CIDs) in REGISTRY."
  (fset:size (registry-definitions registry)))

(defun map-verbs (function registry)
  "Call FUNCTION with each VERB-DEFINITION in REGISTRY, in CID order."
  (fset:do-map (cid def (registry-definitions registry))
    (declare (ignore cid))
    (funcall function def))
  registry)

(defun ensure-verb-registry (world)
  "Return WORLD's verb registry, creating an empty one on first use.
WORLD's registry lives in its transient WORLD-VERB-REGISTRY slot."
  (or (world-verb-registry world)
      (setf (world-verb-registry world) (make-verb-registry))))

;;; ------------------------------------------------------------------
;;; Name index
;;; ------------------------------------------------------------------

(defun verb-name-cid (registry name)
  "CID currently bound to NAME (a symbol) in REGISTRY, or NIL."
  (and (symbolp name)
       (fset:lookup (registry-names registry) name)))

(defun bind-verb-name (registry name cid)
  "Point NAME at CID in REGISTRY, recording the previous binding in the
history (newest first).  Returns CID."
  (setf (registry-names registry)
        (fset:with (registry-names registry) name cid))
  (let ((history (fset:lookup (registry-history registry) name)))
    (setf (registry-history registry)
          (fset:with (registry-history registry) name
                     (cons cid (remove cid history :test #'string=)))))
  cid)

(defun verb-history (registry name)
  "List of CIDs NAME has been bound to in REGISTRY, newest first."
  (fset:lookup (registry-history registry) name))

(defun verb-names (registry cid-or-definition)
  "Names currently bound to the CID of CID-OR-DEFINITION in REGISTRY.
CID-OR-DEFINITION may be a CID string, a VERB-DEFINITION, or a verb NAME."
  (let ((cid (etypecase cid-or-definition
               (string cid-or-definition)
               (verb-definition (verb-definition-cid cid-or-definition))
               (symbol (verb-cid registry cid-or-definition))))
        (names '()))
    (when cid
      (fset:do-map (name bound (registry-names registry))
        (when (string= bound cid)
          (push name names)))
      (sort names #'string< :key #'symbol-name))))

;;; ------------------------------------------------------------------
;;; Definition lookup
;;; ------------------------------------------------------------------

(defun find-verb (registry name-or-cid)
  "Return the VERB-DEFINITION named or addressed by NAME-OR-CID, or NIL.
A string is treated as a CID; a symbol is resolved through the name index."
  (let ((cid (etypecase name-or-cid
               (string name-or-cid)
               (symbol (verb-name-cid registry name-or-cid)))))
    (and cid (fset:lookup (registry-definitions registry) cid))))

(defun verb-cid (registry name-or-cid)
  "CID addressed by NAME-OR-CID, or NIL."
  (let ((def (find-verb registry name-or-cid)))
    (and def (verb-definition-cid def))))

(defun verb-source (registry name-or-cid)
  "Source form of the verb addressed by NAME-OR-CID."
  (verb-definition-source (find-verb registry name-or-cid)))

(defun verb-docstring (registry name-or-cid)
  "Docstring of the verb addressed by NAME-OR-CID."
  (verb-definition-docstring (find-verb registry name-or-cid)))

(defun verb-references (registry name-or-cid)
  "Alist (SYMBOL . CID) of the resolved references of NAME-OR-CID."
  (verb-definition-references (find-verb registry name-or-cid)))

(defun verb-unresolved-references (registry name-or-cid)
  "Free function symbols of NAME-OR-CID that were not resolved to a verb."
  (verb-definition-unresolved-references (find-verb registry name-or-cid)))

(defun verb-referrers (registry cid-or-definition)
  "Names whose current definition references CID-OR-DEFINITION.
CID-OR-DEFINITION may be a CID string, a VERB-DEFINITION, or a verb NAME
(a symbol, resolved through the name index).  The answer is based on the
CID, so it is naming-independent: renaming a verb does not change it."
  (let ((cid (etypecase cid-or-definition
               (string cid-or-definition)
               (verb-definition (verb-definition-cid cid-or-definition))
               (symbol (verb-cid registry cid-or-definition))))
        (out '()))
    (when cid
      (fset:do-map (name bound (registry-names registry))
        (let ((def (fset:lookup (registry-definitions registry) bound)))
          (when (and def
                     ;; NB: ASSOC's :key is applied to the CAR of each
                     ;; element; FIND's :key is applied to the element
                     ;; itself, which is what we want here.
                     (find cid (verb-definition-references def)
                           :test #'string= :key #'cdr))
            (push name out)))))
    (sort (remove-duplicates out) #'string< :key #'symbol-name)))

;;; ------------------------------------------------------------------
;;; Defining verbs
;;; ------------------------------------------------------------------

(defun leading-docstring (body)
  "The leading docstring of BODY (a list of forms), or NIL.
A leading string literal is a docstring, as in DEFUN, and is reported by
VERB-DOCSTRING.  Unlike a DEFUN docstring it *does* stay in the body and so
*does* take part in the CID: the documentation is content, which means two
verbs that differ only in their docstring are different definitions, and a
name can be re-bound to a re-documented version."
  (if (and body (stringp (first body)))
      (first body)
      nil))

(defun analyze-verb-source (registry source)
  "Resolve free function references in SOURCE against REGISTRY and hash it.
Returns (values CID REFERENCES UNRESOLVED): the content identifier, the
alist (SYMBOL . CID) of references that were resolved (sorted by symbol
name), and the sorted list of free function symbols REGISTRY did not know.

The resolver is consulted for every free identifier — CL-CM guarantees it is
never consulted for a bound one or for quoted data — so this sees all of
them."
  (let ((refs '())
        (free '()))
    (let ((cl-cm:*reference-resolver*
            (lambda (namespace symbol)
              (when (eq namespace :function)
                (pushnew symbol free)
                (let ((cid (verb-name-cid registry symbol)))
                  (when cid
                    (pushnew (cons symbol cid) refs :key #'car)
                    cid))))))
      (let ((cid (cl-cm:code-cid source)))
        (values cid
                (sort refs #'string< :key (lambda (p) (symbol-name (car p))))
                (sort (set-difference free (mapcar #'car refs))
                      #'string< :key #'symbol-name))))))

(defun register-verb (registry name lambda-list body &key strict)
  "Define (or redefine) the verb NAME in REGISTRY and return its
VERB-DEFINITION.

LAMBDA-LIST and BODY are the verb's parameters and forms; BODY may begin
with a docstring (DEFUN convention), which is reported by VERB-DOCSTRING.
The whole body — docstring included — is content, so it takes part in the
CID.  The verb's CID is computed with CL-CM after resolving every free
function reference to the CID currently bound to that name in REGISTRY, so
a reference is to a *version*, not to a name.

If a verb with the same CID already exists, REGISTRY reuses that definition
(deduplication) and merely points NAME at it.  When STRICT is true, an
error is signalled if any free function reference could not be resolved to
a registered verb."
  (check-type name symbol)
  (let ((source `(lambda ,lambda-list ,@body)))
    (multiple-value-bind (cid references unresolved)
        (analyze-verb-source registry source)
      (when (and strict unresolved)
        (error "register-verb: ~A refers to undefined verb~:P ~{~A~^, ~}."
               name unresolved))
      (let ((existing (fset:lookup (registry-definitions registry) cid)))
        (if existing
            (progn
              (bind-verb-name registry name cid)
              existing)
            (let ((definition
                    (make-instance 'verb-definition
                                   :cid cid
                                   :name name
                                   :lambda-list lambda-list
                                   :body body
                                   :source source
                                   :docstring (leading-docstring body)
                                   :references references
                                   :unresolved-references unresolved
                                   :created-at (get-universal-time))))
              (setf (registry-definitions registry)
                    (fset:with (registry-definitions registry) cid definition))
              (bind-verb-name registry name cid)
              definition))))))

(defmacro define-verb (registry name lambda-list &body body)
  "Define the verb NAME in REGISTRY with LAMBDA-LIST and BODY.
Expands to REGISTER-VERB; see it for the docstring convention and how
references are resolved."
  `(register-verb ,registry ',name ',lambda-list ',body))
