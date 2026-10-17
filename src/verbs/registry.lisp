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
;;;; There is no separate registry object: a "verb registry" IS a
;;;; CL-CM-DB:CODE-DATABASE.  The database is exactly the right shape:
;;;;
;;;;   * a verb NAME is an *identity* in the database, so its append-only
;;;;     identity log records every definition and redefinition (and is the
;;;;     source of VERB-HISTORY);
;;;;   * the verb's SOURCE is stored, content-addressed, in the database's
;;;;     object store — identical code is stored once, however many names
;;;;     point at it, and old versions remain addressable by CID;
;;;;   * the database doubles as CL-CM's reference resolver, so a
;;;;     definition's CID is recursively content addressed;
;;;;   * the database compiles and caches the code, wiring each definition's
;;;;     references to the compiled function of the referenced CID.
;;;;
;;;; Definitions are rebuilt from the database on demand; Apeiron adds no
;;;; state of its own.  See ENSURE-VERB-REGISTRY for how a world gets its
;;;; database.

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
  (:documentation "A view of one stored verb: its identity (CID), the name it
was looked up by, its source, and the references it resolved.  Definitions
are rebuilt from the database on demand; nothing here is persisted."))

(defmethod print-object ((def verb-definition) stream)
  (print-unreadable-object (def stream :type t)
    (format stream "~A ~A" (verb-definition-name def) (verb-definition-cid def))))

;;; ------------------------------------------------------------------
;;; Opening a verb database
;;; ------------------------------------------------------------------

(defvar *verb-database-counter* 0
  "Makes each standalone registry's temporary database directory unique.")

(defun default-verb-database-directory ()
  "Where a world's verb database lives by default: DATA/VERBS/."
  (merge-pathnames "verbs/" *data-directory*))

(defun fresh-verb-database-directory ()
  "A brand-new temporary directory for a standalone registry."
  (merge-pathnames
   (format nil "apeiron-verbs-~D-~D/"
           (get-universal-time) (incf *verb-database-counter*))
   (uiop:temporary-directory)))

(defun make-verb-registry (&key database directory (name "verbs"))
  "Return a CL-CM-DB:CODE-DATABASE to use as a verb registry.

A verb registry has no state beyond the code database: names are
identities, definitions are code objects, history is the identity log, and
compiled functions are cached by the database.  DATABASE, when supplied, is
used as-is.  Otherwise a database named NAME is opened under DIRECTORY;
when DIRECTORY is not supplied a fresh temporary directory is used, which
keeps standalone registries (tests, scratch use) from writing into the
project.  Worlds pass their own directory through ENSURE-VERB-REGISTRY."
  (let ((database (or database
                      (cl-cm-db:make-database
                       :directory (or directory (fresh-verb-database-directory))
                       :name name))))
    (cl-cm-db:ensure-database database)))

(defun verb-registry-directory (registry)
  "Directory holding REGISTRY's identity log and code store."
  (uiop:pathname-directory-pathname
   (cl-cm-db:identity-log-path registry)))

(defun ensure-verb-registry (world &key directory)
  "Return WORLD's verb database, opening it on first use.
WORLD's registry lives in its transient WORLD-VERB-REGISTRY slot and is a
CL-CM-DB:CODE-DATABASE.  The directory is DIRECTORY when supplied, else
WORLD's :VERB-DIRECTORY config value, else
DEFAULT-VERB-DATABASE-DIRECTORY."
  (or (world-verb-registry world)
      (setf (world-verb-registry world)
            (make-verb-registry
             :directory (or directory
                            (get-config-key world :verb-directory)
                            (default-verb-database-directory))))))

;;; ------------------------------------------------------------------
;;; Identity keys and names
;;; ------------------------------------------------------------------

(defun split-identity-key (key)
  "Split a CL-CM-DB identity key into (values PACKAGE-NAME NAME)."
  (let ((separator (search "::" key :from-end t)))
    (when separator
      (values (subseq key 0 separator)
              (subseq key (+ separator 2))))))

(defun identity-key-symbol (key)
  "The symbol an identity KEY names, or NIL when its package is absent.

Identity keys are strings (`PKG::NAME', or `#::NAME' for an uninterned
symbol) so they can be read back without the packages that produced them.
This turns one back into a symbol when that package exists in the image."
  (multiple-value-bind (package-name symbol-name) (split-identity-key key)
    (cond
      ((null package-name) nil)
      ((string= package-name "#") (make-symbol symbol-name))
      (t
       (let ((package (find-package package-name)))
         (when package
           (multiple-value-bind (symbol status)
               (find-symbol symbol-name package)
             (if (and symbol (member status '(:internal :external)))
                 symbol
                 (make-symbol symbol-name)))))))))

(defun names-for-cid (registry cid)
  "Symbols currently bound to CID in REGISTRY, sorted by name."
  (let ((names '()))
    (maphash (lambda (key value)
               (when (string= value cid)
                 (let ((symbol (identity-key-symbol key)))
                   (when symbol
                     (pushnew symbol names)))))
             (cl-cm-db:database-identities registry))
    (sort names #'string< :key #'symbol-name)))

;;; ------------------------------------------------------------------
;;; Name index and history
;;; ------------------------------------------------------------------

(defun verb-name-cid (registry name)
  "CID currently bound to NAME (a symbol) in REGISTRY, or NIL."
  (and (symbolp name)
       (cl-cm-db:identity-cid name registry)))

(defun read-identity-records (registry)
  "Read REGISTRY's identity log as a list of records, oldest first."
  (let ((path (cl-cm-db:identity-log-path registry)))
    (when (probe-file path)
      (with-open-file (in path :direction :input)
        (let ((*read-eval* nil))
          (loop for record = (read in nil :eof)
                until (eq record :eof)
                collect record))))))

(defun verb-history (registry name)
  "List of CIDs NAME has been bound to in REGISTRY, newest first."
  (let ((key (cl-cm-db:identity-key name)))
    (remove-duplicates
     (loop for record in (reverse (read-identity-records registry))
           when (and (consp record)
                     (member (first record) '(:define :set))
                     (string= (third record) key)
                     (stringp (fourth record)))
             collect (fourth record))
     :test #'string=)))

(defun verb-names (registry cid-or-definition)
  "Names currently bound to the CID of CID-OR-DEFINITION in REGISTRY.
CID-OR-DEFINITION may be a CID string, a VERB-DEFINITION, or a verb NAME."
  (let ((cid (etypecase cid-or-definition
               (string cid-or-definition)
               (verb-definition (verb-definition-cid cid-or-definition))
               (symbol (verb-cid registry cid-or-definition)))))
    (if cid
        (names-for-cid registry cid)
        '())))

;;; ------------------------------------------------------------------
;;; Definition lookup
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

(defun make-verb-definition (registry cid &optional name)
  "Build the VERB-DEFINITION for CID, or NIL when CID holds no verb code."
  (let ((source (cl-cm-db:code-by-cid registry cid)))
    (when (and (consp source) (eq (first source) 'lambda))
      (let ((lambda-list (second source))
            (body (cddr source)))
        (multiple-value-bind (references unresolved) (cl-cm-db:code-references registry cid)
          (make-instance 'verb-definition
                         :cid cid
                         :name (or name (first (names-for-cid registry cid)))
                         :lambda-list lambda-list
                         :body body
                         :source source
                         :docstring (leading-docstring body)
                         :references references
                         :unresolved-references unresolved
                         :created-at 0))))))

(defun find-verb (registry name-or-cid)
  "Return the VERB-DEFINITION named or addressed by NAME-OR-CID, or NIL.
A string is treated as a CID; a symbol is resolved through the name index."
  (let ((cid (etypecase name-or-cid
               (string name-or-cid)
               (symbol (verb-name-cid registry name-or-cid)))))
    (and cid
         (make-verb-definition registry cid
                               (and (symbolp name-or-cid) name-or-cid)))))

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
      (maphash (lambda (key bound-cid)
                 (let ((def (make-verb-definition registry bound-cid)))
                   (when (and def
                              (find cid (verb-definition-references def)
                                    :test #'string= :key #'cdr))
                     (let ((name (identity-key-symbol key)))
                       (when name (push name out))))))
               (cl-cm-db:database-identities registry)))
    (sort (remove-duplicates out) #'string< :key #'symbol-name)))

;;; ------------------------------------------------------------------
;;; Defining verbs
;;; ------------------------------------------------------------------

(defun register-verb (registry name lambda-list body &key strict)
  "Define (or redefine) the verb NAME in REGISTRY and return its
VERB-DEFINITION.

LAMBDA-LIST and BODY are the verb's parameters and forms; BODY may begin
with a docstring (DEFUN convention), which is reported by VERB-DOCSTRING.
The whole body — docstring included — is content, so it takes part in the
CID.  The verb's CID is computed by CL-CM after resolving every free
reference to the CID currently bound to that name, so a reference is to a
*version*, not to a name.

The definition is stored in REGISTRY, a CL-CM-DB code database: a new name
is a `:define' record in its identity log, an existing name a `:set'
record.  Storing identical code is a no-op, so several names can point at
one definition.  When STRICT is true, an error is signalled if any free
function reference could not be resolved to a registered verb."
  (check-type name symbol)
  (let ((source `(lambda ,lambda-list ,@body)))
    (multiple-value-bind (references unresolved) (cl-cm-db:source-references registry source)
      (declare (ignore references))
      (when (and strict unresolved)
        (error "register-verb: ~A refers to undefined verb~:P ~{~A~^, ~}."
               name unresolved))
      (let ((current (verb-name-cid registry name)))
        (cond ((null current)
               (cl-cm-db:defidentity registry name source))
              ((not (string= current (cl-cm-db:database-code-cid registry source)))
               (cl-cm-db:setidentity registry name source))))
      (find-verb registry name))))

(defmacro define-verb (registry name lambda-list &body body)
  "Define the verb NAME in REGISTRY with LAMBDA-LIST and BODY.
Expands to REGISTER-VERB; see it for the docstring convention and how
references are resolved."
  `(register-verb ,registry ',name ',lambda-list ',body))

;;; ------------------------------------------------------------------
;;; Invocation
;;; ------------------------------------------------------------------

(defun verb-function (registry name-or-cid)
  "Return the compiled function of the verb addressed by NAME-OR-CID in
REGISTRY, compiling and caching it in the database on first use.

The database wires each free reference to a call-time lookup of the
compiled function of the referenced CID, so an already-compiled caller keeps
reaching the version it was compiled against even after a callee is
redefined."
  (let ((cid (etypecase name-or-cid
               (string name-or-cid)
               (symbol (verb-name-cid registry name-or-cid)))))
    (unless cid
      (error "No such verb: ~S" name-or-cid))
    (cl-cm-db:code-function registry cid)))

(defun call-verb (registry name-or-cid &rest arguments)
  "Call the verb addressed by NAME-OR-CID in REGISTRY with ARGUMENTS.
Returns whatever the verb returns (including multiple values)."
  (apply (verb-function registry name-or-cid) arguments))

;;; ------------------------------------------------------------------
;;; Whole-registry queries
;;; ------------------------------------------------------------------

(defun verb-count (registry)
  "Number of distinct definitions (CIDs) stored in REGISTRY."
  (hash-table-count (cl-cm-db:database-code registry)))

(defun map-verbs (function registry)
  "Call FUNCTION with each VERB-DEFINITION in REGISTRY, in CID order."
  (let ((cids '()))
    (maphash (lambda (cid entry)
               (declare (ignore entry))
               (push cid cids))
             (cl-cm-db:database-code registry))
    (dolist (cid (sort cids #'string<))
      (let ((definition (make-verb-definition registry cid)))
        (when definition
          (funcall function definition)))))
  registry)