;;;; src/verbs/verbs.lisp — verb sugar over cl-cm-db
;;;;
;;;; The verb store, its identities, history, references, compiled code and
;;;; reverse lookups all live in CL-CM-DB.  What remains here is the little
;;;; bit of MUD-specific sugar:
;;;;
;;;;   * DEFINE-VERB / REGISTER-VERB turn a lambda list + body into a
;;;;     stored `(lambda ...)' identity, with the DEFUN docstring convention
;;;;     (a leading body string is content and is reported by
;;;;     VERB-DOCSTRING);
;;;;   * ENSURE-VERB-REGISTRY opens a world's database.
;;;;
;;;; Everything else — FIND-VERB's replacement DEFINITION-BY-IDENTITY /
;;;; DEFINITION-BY-CID, CODE-REFERENCES, CODE-REFERRERS, IDENTITY-HISTORY,
;;;; IDENTITY-NAMES-FOR-CID, CODE-FUNCTION, CALL-IDENTITY — is used
;;;; directly from CL-CM-DB.

(in-package #:apeiron.verbs)

(defun leading-docstring (body)
  "The leading docstring of BODY (a list of forms), or NIL."
  (if (and body (stringp (first body)))
      (first body)
      nil))

(defun verb-docstring (definition)
  "The docstring of DEFINITION (a CL-CM-DB:CODE-DEFINITION), or NIL.
A leading string in the body is a docstring, as in DEFUN.  It stays in the
body and therefore takes part in the CID: the documentation is content."
  (leading-docstring (cl-cm-db:code-definition-body definition)))

(defun register-verb (registry name lambda-list body &key strict)
  "Define (or redefine) the verb NAME in REGISTRY and return its
CL-CM-DB:CODE-DEFINITION.

LAMBDA-LIST and BODY are the verb's parameters and forms; BODY may begin
with a docstring (DEFUN convention), reported by VERB-DOCSTRING.  The whole
body — docstring included — is content, so it takes part in the CID.

REGISTRY is a CL-CM-DB code database.  The definition is stored with
CL-CM-DB:ENSURE-IDENTITY, so a new name gets a `:define' record, an existing
one a `:set' record, and re-storing identical content is a no-op.  When
STRICT is true, an error is signalled if any free function reference could
not be resolved to a registered identity."
  (check-type name symbol)
  (let ((source `(lambda ,lambda-list ,@body)))
    (when strict
      (multiple-value-bind (references unresolved)
          (cl-cm-db:source-references registry source)
        (declare (ignore references))
        (when unresolved
          (error "register-verb: ~A refers to undefined verb~:P ~{~A~^, ~}."
                 name unresolved))))
    (cl-cm-db:ensure-identity registry name source)
    (cl-cm-db:definition-by-identity name registry)))

(defmacro define-verb (registry name lambda-list &body body)
  "Define the verb NAME in REGISTRY with LAMBDA-LIST and BODY.
Expands to REGISTER-VERB; see it for the docstring convention and how
references are resolved."
  `(register-verb ,registry ',name ',lambda-list ',body))

;;; ------------------------------------------------------------------
;;; A world's database
;;; ------------------------------------------------------------------

(defun default-verb-database-directory ()
  "Where a world's verb database lives by default: DATA/VERBS/."
  (merge-pathnames "verbs/" *data-directory*))

(defun ensure-verb-registry (world &key directory)
  "Return WORLD's verb database, opening it on first use.
WORLD's registry lives in its transient WORLD-VERB-REGISTRY slot and is a
CL-CM-DB:CODE-DATABASE.  The directory is DIRECTORY when supplied, else
WORLD's :VERB-DIRECTORY config value, else
DEFAULT-VERB-DATABASE-DIRECTORY."
  (or (world-verb-registry world)
      (setf (world-verb-registry world)
            (cl-cm-db:ensure-database
             (cl-cm-db:make-database
              :directory (or directory
                             (get-config-key world :verb-directory)
                             (default-verb-database-directory))
              :name "verbs")))))
