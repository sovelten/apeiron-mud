;;;; src/verbs/integration.lisp — verbs on MUD objects
;;;;
;;;; An object's VERBS slot is an immutable FSET map from a verb name to the
;;;; CID of its definition (see APEIRON.CORE:OBJECT-VERBS and friends).  The
;;;; code lives once, in the world's registry — a CL-CM-DB code database —
;;;; and the object only names the versions it answers to.  Rebinding the
;;;; map is what BKNR records, so an object's verb bindings persist like any
;;;; other slot; the definitions they name persist in the code database.

(in-package #:apeiron.verbs)

(defmacro object-define-verb! (registry object name lambda-list &body body)
  "Register a verb NAME (with LAMBDA-LIST and BODY) in REGISTRY and bind it
on OBJECT.  Returns the CL-CM-DB:CODE-DEFINITION.  This is how an object
gains its own way of answering a command: the definition is
content-addressed and shared, OBJECT just points at it.

NAME is a literal symbol, as in DEFINE-VERB, and BODY may begin with a
docstring.  REGISTRY and OBJECT are ordinary expressions, each evaluated
once:

    (object-define-verb! (ensure-verb-registry world) lamp 'light
      (&optional who)
      \"Light the lamp, optionally telling WHO.\"
      (set-lamp-lit lamp t)
      (when who (tell who \"The lamp flickers to life.\")))"
  (let ((definition (gensym "DEFINITION-")))
    `(let ((,definition (register-verb ,registry ',name ',lambda-list ',body)))
       (object-set-verb ,object ',name (cl-cm-db:code-definition-cid ,definition))
       ,definition)))

(defun object-bind-verb! (object name cid)
  "Bind NAME on OBJECT to the already-registered CID.  Returns CID.
Use this to share a definition between objects, or to pin one object to a
specific version while another object moves on."
  (object-set-verb object name cid))

(defun object-verb (registry object name)
  "Return the CL-CM-DB:CODE-DEFINITION OBJECT binds to NAME in REGISTRY, or NIL."
  (let ((cid (object-verb-cid object name)))
    (and cid (cl-cm-db:definition-by-cid registry cid))))

(defun object-call-verb (registry object name &rest arguments)
  "Call the verb OBJECT binds to NAME with ARGUMENTS, resolving nested verb
references through REGISTRY.  Returns whatever the verb returns."
  (let ((cid (object-verb-cid object name)))
    (unless cid
      (error "~A has no ~A verb." (object-name object) name))
    (apply (cl-cm-db:code-function registry cid) arguments)))

;;; ------------------------------------------------------------------
;;; The world's database
;;; ------------------------------------------------------------------
;;;
;;; Persistence needs no code here: a world's registry IS a CL-CM-DB code
;;; database, which writes its identity log and content-addressed object
;;; store itself.  ENSURE-VERB-REGISTRY opens it (see verbs.lisp); object
;;; bindings are name -> CID and are persisted by BKNR as ordinary slot
;;; writes.  Both halves therefore line up after a restart without a
;;; serialization step.
