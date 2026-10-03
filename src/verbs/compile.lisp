;;;; src/verbs/compile.lisp — compiling and calling verbs
;;;;
;;;; A verb's source is a plain `(lambda ...)'; its free references are
;;;; wired at compile time by name to a small wrapper that dispatches, at
;;;; call time, to the function of the REFERENCED CID through the registry
;;;; in effect.  So a verb call always reaches the version it was compiled
;;;; against — a redefinition of the callee, even under the same name, does
;;;; not change what an already-compiled caller calls.

(in-package #:apeiron.verbs)

(defvar *verb-registry* nil
  "The verb registry in effect while a verb's compiled function runs.
Bound by the wrapper VERB-FUNCTION returns, so nested verb references
resolve through the same registry.")

(declaim (ftype (function (t t) function) verb-function))

(defun verb-function (registry name-or-cid)
  "Return the compiled function of the verb addressed by NAME-OR-CID in
REGISTRY, compiling and caching it on first use.

The returned function binds *VERB-REGISTRY* to REGISTRY around each call, so
the wrappers that wire the verb's references dispatch to the right CIDs.  The
cache is keyed by CID, so two names for the same verb share one function."
  (let* ((definition (or (find-verb registry name-or-cid)
                         (error "No such verb: ~S" name-or-cid)))
         (cid (verb-definition-cid definition)))
    (or (gethash cid (registry-functions registry))
        (let* ((references (verb-definition-references definition))
               (ref-names (mapcar #'car references))
               (args (gensym "VERB-ARGS-"))
               (lambda-form `(lambda ,(verb-definition-lambda-list definition)
                               ,@(verb-definition-body definition)))
               ;; A verb may reference a verb whose NAME is a symbol of a
               ;; locked package — (get ...) is CL:GET, (describe ...) is
               ;; CL:DESCRIBE, ...  FLET-binding such a name is exactly what
               ;; pins the reference to a CID, but SBCL's package lock
               ;; rejects the binding.  Disable the lock for precisely those
               ;; names in this compilation unit (SBCL only).
               (declarations
                 #+sbcl (when references
                          `((declare (sb-ext:disable-package-locks ,@ref-names))))
                 #-sbcl nil)
               ;; Each referenced name gets a local function that applies the
               ;; callee's compiled function (looked up by CID) to the args.
               ;; The FLET wraps the verb lambda in a nullary lambda so the
               ;; whole thing is a valid argument to COMPILE.
               (wired (if references
                          `(flet (,@(loop for (name . ref-cid) in references
                                          collect `(,name (&rest ,args)
                                                    (apply (verb-function *verb-registry* ,ref-cid)
                                                           ,args))))
                             (function ,lambda-form))
                          `(function ,lambda-form)))
               (inner (funcall (compile nil `(lambda () ,@declarations ,wired))))
               (function (lambda (&rest arguments)
                           (let ((*verb-registry* registry))
                             (apply inner arguments)))))
          (setf (gethash cid (registry-functions registry)) function)
          function))))

(defun call-verb (registry name-or-cid &rest arguments)
  "Call the verb addressed by NAME-OR-CID in REGISTRY with ARGUMENTS.
Returns whatever the verb returns (including multiple values)."
  (apply (verb-function registry name-or-cid) arguments))
