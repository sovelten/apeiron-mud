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
;;;; Storage is delegated to CL-CM-DB, the content-addressed code database
;;;; that ships with CL-CM.  A VERB-REGISTRY is a thin wrapper around a
;;;; CL-CM-DB:CODE-DATABASE:
;;;;
;;;;   * a verb NAME is an *identity* in the database, so the database's
;;;;     append-only identity log records every definition and redefinition
;;;;     (and is the source of VERB-HISTORY);
;;;;   * the verb's SOURCE is stored, content-addressed, in the database's
;;;;     object store — identical code is stored once, however many names
;;;;     point at it, and old versions remain addressable by CID;
;;;;   * the database doubles as CL-CM's reference resolver, so a
;;;;     definition's CID is recursively content addressed.
;;;;
;;;; The registry keeps no persistent state of its own.  Definitions are
;;;; rebuilt from the database on demand, and only compiled functions are
;;;; cached (transiently).  See ENSURE-VERB-REGISTRY for how a world gets
;;;; its database.

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
;;; The registry (a thin wrapper around a cl-cm-db code database)
;;; ------------------------------------------------------------------

(defclass verb-registry ()
  ((database :initarg :database :reader verb-registry-database
             :documentation "The CL-CM-DB:CODE-DATABASE that stores verb
identities and code.")
   (functions :initform (make-hash-table :test #'equal)
              :accessor registry-functions
              :documentation "Transient cache: cid -> compiled function.")
   (references :initform (make-hash-table :test #'equal)
               :accessor registry-references
               :documentation "Transient cache: cid -> (REFERENCES . UNRESOLVED),
resolved against the identity table as it was when CID was stored."))
  (:documentation "A content-addressed store of verbs, backed by a
CL-CM-DB code database.  See the file header."))

(defmethod print-object ((reg verb-registry) stream)
  (print-unreadable-object (reg stream :type t)
    (format stream "~D verb~:P" (verb-count reg))))

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
  "Return a verb registry backed by a CL-CM-DB code database.

DATABASE, when supplied, is used as-is.  Otherwise a database named NAME is
opened under DIRECTORY; when DIRECTORY is not supplied a fresh temporary
directory is used, which keeps standalone registries (tests, scratch use)
from writing into the project.  Worlds pass their own directory through
ENSURE-VERB-REGISTRY."
  (let ((database (or database
                      (cl-cm-db:make-database
                       :directory (or directory (fresh-verb-database-directory))
                       :name name))))
    (cl-cm-db:ensure-database database)
    (make-instance 'verb-registry :database database)))

(defun verb-registry-directory (registry)
  "Directory holding REGISTRY's identity log and code store."
  (uiop:pathname-directory-pathname
   (cl-cm-db:identity-log-path (verb-registry-database registry))))

(defun ensure-verb-registry (world &key directory)
  "Return WORLD's verb registry, opening its database on first use.
WORLD's registry lives in its transient WORLD-VERB-REGISTRY slot.  The
database directory is DIRECTORY when supplied, else WORLD's :VERB-DIRECTORY
config value, else DEFAULT-VERB-DATABASE-DIRECTORY."
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
             (cl-cm-db:database-identities (verb-registry-database registry)))
    (sort names #'string< :key #'symbol-name)))

;;; ------------------------------------------------------------------
;;; Name index and history
;;; ------------------------------------------------------------------

(defun verb-name-cid (registry name)
  "CID currently bound to NAME (a symbol) in REGISTRY, or NIL."
  (and (symbolp name)
       (cl-cm-db:identity-cid name (verb-registry-database registry))))

(defun read-identity-records (registry)
  "Read REGISTRY's identity log as a list of records, oldest first."
  (let ((path (cl-cm-db:identity-log-path (verb-registry-database registry))))
    (when (probe-file path)
      (with-open-file (in path :direction :input)
        (let ((*read-eval* nil))
          (loop for record = (read in nil :eof)
                until (eq record :eof)
                collect record))))))

(defun apply-identity-record-to (identities record)
  "Fold one identity-log RECORD into the IDENTITIES hash table."
  (when (and (consp record) (stringp (third record)))
    (case (first record)
      (:retract (remhash (third record) identities))
      ((:define :set)
       (when (stringp (fourth record))
         (setf (gethash (third record) identities) (fourth record)))))))

(defun identities-before-cid (registry cid)
  "The identity table as it was when CID was first stored.

The identity log is replayable, so this folds the records that precede the
first one mentioning CID.  Those are exactly the identities CL-CM resolved
against when it computed CID, which is how a stored definition's references
are recovered even after the names it mentions have moved on."
  (let ((identities (make-hash-table :test #'equal)))
    (dolist (record (read-identity-records registry) identities)
      (when (and (member (first record) '(:define :set))
                 (stringp (fourth record))
                 (string= (fourth record) cid))
        (return identities))
      (apply-identity-record-to identities record))))

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

(defun record-references (registry source &optional identities)
  "Walk SOURCE, returning the resolved and unresolved free function refs.

Uses CL-CM's reference resolver exactly as the database does (so an
identity is resolved in either namespace), but records only function
positions.  IDENTITIES defaults to the database's current table; callers
reconstructing a stored definition pass the table as of its CID instead.
Returns (values REFERENCES UNRESOLVED), where REFERENCES is a sorted alist
(SYMBOL . CID) and UNRESOLVED is a sorted list of symbols."
  (let ((references '())
        (free '())
        (identities (or identities
                        (cl-cm-db:database-identities
                         (verb-registry-database registry)))))
    (let ((cl-cm:*reference-resolver*
            (lambda (namespace symbol)
              (let ((cid (gethash (cl-cm-db:identity-key symbol) identities)))
                (when (eq namespace :function)
                  (pushnew symbol free)
                  (when cid
                    (pushnew (cons symbol cid) references :key #'car)))
                cid))))
      (cl-cm:normalize-code source))
    (values (sort references #'string< :key (lambda (pair) (symbol-name (car pair))))
            (sort (set-difference free (mapcar #'car references))
                  #'string< :key #'symbol-name))))

(defun stored-code-by-cid (database cid)
  "The source expression CL-CM-DB stored for CID, or NIL.

Uses CL-CM-DB:CODE-BY-CID when the loaded cl-cm provides it (the normal
case), and otherwise the code entry's source accessor, so Apeiron keeps
working against a cl-cm checkout from before that convenience function was
exported."
  (let ((code-by-cid (find-symbol "CODE-BY-CID" :cl-cm-db)))
    (if (and code-by-cid (fboundp code-by-cid))
        (funcall code-by-cid database cid)
        (let ((entry (gethash cid (cl-cm-db:database-code database)))
              (source (find-symbol "CODE-ENTRY-SOURCE" :cl-cm-db)))
          (when (and entry source (fboundp source))
            (funcall source entry))))))

(defun references-for-cid (registry cid source)
  "References SOURCE had when it was stored as CID.
Values as RECORD-REFERENCES.  Cached per CID, since a content-addressed
definition's references never change."
  (let ((cached (gethash cid (registry-references registry))))
    (if cached
        (values (car cached) (cdr cached))
        (multiple-value-bind (references unresolved)
            (record-references registry source (identities-before-cid registry cid))
          (setf (gethash cid (registry-references registry))
                (cons references unresolved))
          (values references unresolved)))))

(defun make-verb-definition (registry cid &optional name)
  "Build the VERB-DEFINITION for CID, or NIL when CID holds no verb code."
  (let ((source (stored-code-by-cid (verb-registry-database registry) cid)))
    (when (and (consp source) (eq (first source) 'lambda))
      (let ((lambda-list (second source))
            (body (cddr source)))
        (multiple-value-bind (references unresolved) (references-for-cid registry cid source)
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
               (cl-cm-db:database-identities (verb-registry-database registry))))
    (sort (remove-duplicates out) #'string< :key #'symbol-name)))

;;; ------------------------------------------------------------------
;;; Defining verbs
;;; ------------------------------------------------------------------

(defun analyze-verb-source (registry source)
  "Resolve free references in SOURCE against REGISTRY and hash it.
Returns (values CID REFERENCES UNRESOLVED): the content identifier, the
alist (SYMBOL . CID) of references that were resolved (sorted by symbol
name), and the sorted list of free function symbols REGISTRY did not know.

The CID is computed by the database (CL-CM-DB:DATABASE-CODE-CID), so it is
exactly the CID the database will assign when the source is stored."
  (multiple-value-bind (references unresolved) (record-references registry source)
    (values (cl-cm-db:database-code-cid (verb-registry-database registry) source)
            references
            unresolved)))

(defun register-verb (registry name lambda-list body &key strict)
  "Define (or redefine) the verb NAME in REGISTRY and return its
VERB-DEFINITION.

LAMBDA-LIST and BODY are the verb's parameters and forms; BODY may begin
with a docstring (DEFUN convention), which is reported by VERB-DOCSTRING.
The whole body — docstring included — is content, so it takes part in the
CID.  The verb's CID is computed by CL-CM after resolving every free
reference to the CID currently bound to that name, so a reference is to a
*version*, not to a name.

The definition is stored in the registry's CL-CM-DB database: a new name is
a `:define' record in its identity log, an existing name a `:set' record.
Storing identical code is a no-op, so several names can point at one
definition.  When STRICT is true, an error is signalled if any free function
reference could not be resolved to a registered verb."
  (check-type name symbol)
  (let ((source `(lambda ,lambda-list ,@body)))
    (multiple-value-bind (cid references unresolved)
        (analyze-verb-source registry source)
      (declare (ignore references))
      (when (and strict unresolved)
        (error "register-verb: ~A refers to undefined verb~:P ~{~A~^, ~}."
               name unresolved))
      (let ((database (verb-registry-database registry))
            (current (verb-name-cid registry name)))
        (cond ((null current)
               (setf cid (cl-cm-db:defidentity database name source)))
              ((not (string= current cid))
               (setf cid (cl-cm-db:setidentity database name source))))
        (find-verb registry name)))))

(defmacro define-verb (registry name lambda-list &body body)
  "Define the verb NAME in REGISTRY with LAMBDA-LIST and BODY.
Expands to REGISTER-VERB; see it for the docstring convention and how
references are resolved."
  `(register-verb ,registry ',name ',lambda-list ',body))

;;; ------------------------------------------------------------------
;;; Whole-registry queries
;;; ------------------------------------------------------------------

(defun verb-count (registry)
  "Number of distinct definitions (CIDs) stored in REGISTRY."
  (hash-table-count (cl-cm-db:database-code (verb-registry-database registry))))

(defun map-verbs (function registry)
  "Call FUNCTION with each VERB-DEFINITION in REGISTRY, in CID order."
  (let ((cids '()))
    (maphash (lambda (cid entry)
               (declare (ignore entry))
               (push cid cids))
             (cl-cm-db:database-code (verb-registry-database registry)))
    (dolist (cid (sort cids #'string<))
      (let ((definition (make-verb-definition registry cid)))
        (when definition
          (funcall function definition)))))
  registry)
