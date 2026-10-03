;;;; src/verbs/integration.lisp — verbs on MUD objects
;;;;
;;;; An object's VERBS slot is an immutable FSET map from a verb name to the
;;;; CID of its definition (see APEIRON.CORE:OBJECT-VERBS and friends).  The
;;;; code lives once, in the world's registry; the object only names the
;;;; versions it answers to.  Rebinding the map is what BKNR records, so an
;;;; object's verb bindings persist like any other slot.

(in-package #:apeiron.verbs)

(defmacro object-define-verb! (registry object name lambda-list &body body)
  "Register a verb NAME (with LAMBDA-LIST and BODY) in REGISTRY and bind it
on OBJECT.  Returns the VERB-DEFINITION.  This is how an object gains its own
way of answering a command: the definition is content-addressed and shared,
OBJECT just points at it.

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
       (object-set-verb ,object ',name (verb-definition-cid ,definition))
       ,definition)))

(defun object-bind-verb! (object name cid)
  "Bind NAME on OBJECT to the already-registered CID.  Returns CID.
Use this to share a definition between objects, or to pin one object to a
specific version while another object moves on."
  (object-set-verb object name cid))

(defun object-verb (registry object name)
  "Return the VERB-DEFINITION OBJECT binds to NAME in REGISTRY, or NIL."
  (let ((cid (object-verb-cid object name)))
    (and cid (find-verb registry cid))))

(defun object-call-verb (registry object name &rest arguments)
  "Call the verb OBJECT binds to NAME with ARGUMENTS, resolving nested verb
references through REGISTRY.  Returns whatever the verb returns."
  (let ((cid (object-verb-cid object name)))
    (unless cid
      (error "~A has no ~A verb." (object-name object) name))
    (apply (verb-function registry cid) arguments)))

;;; ------------------------------------------------------------------
;;; Persisting a world's registry
;;; ------------------------------------------------------------------
;;;
;;; The registry is transient: it caches compiled functions.  Its persistent
;;; form is plain data — VERB-REGISTRY->MAP produces an FSET map of strings,
;;; numbers, lists and nested FSET maps, which the datastore's FSET encoder
;;; (see APEIRON/PERSISTENCE, STORE.LISP) round-trips.  It is stored in the
;;; world's CONFIG map, itself an immutable FSET map, so saving is an
;;; ordinary slot write that BKNR records.

(defparameter *verb-registry-config-key* :verb-registry
  "Key under which a world's serialized verb registry is kept in its CONFIG
map.  See SAVE-VERB-REGISTRY! and LOAD-VERB-REGISTRY!.")

(defun save-verb-registry! (world &key (key *verb-registry-config-key*))
  "Serialize WORLD's verb registry into WORLD's CONFIG map so the datastore
stores it.  Returns the serialized map.

Object verb bindings are name -> CID; the code those CIDs name lives only in
the registry, so persisting the registry is what makes an object's verbs
survive a restart.  Restore it with LOAD-VERB-REGISTRY!."
  (let ((serialized (verb-registry->map (ensure-verb-registry world))))
    (setf (world-config world)
          (fset:with (world-config world) key serialized))
    serialized))

(defun load-verb-registry! (world &key (key *verb-registry-config-key*))
  "Rebuild WORLD's verb registry from the serialized map stored in its CONFIG
map under KEY, and install it in WORLD's WORLD-VERB-REGISTRY slot.  CIDs are
restored verbatim, without re-hashing, so object verb bindings keep
resolving.  Returns the registry, or NIL when nothing is stored."
  (let ((serialized (fset:lookup (world-config world) key)))
    (when serialized
      (setf (world-verb-registry world)
            (map->verb-registry serialized)))))
