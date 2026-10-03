;;;; src/verbs/package.lisp — package for the content-addressed verb registry
;;;;
;;;; Built on CL-CM (content-addressable Common Lisp code): a verb's
;;;; identity is the CID of its definition with free references replaced by
;;;; the CIDs of the verbs it calls, so it is independent of naming.

(defpackage #:apeiron.verbs
  (:use #:cl
        #:apeiron.core)
  (:documentation
   "Content-addressed verbs for the Apeiron MUD.

A *verb* is a named function whose identity is a content identifier (CID)
computed by CL-CM: its body is alpha-renamed (bound-variable names do not
matter) and every free reference to another verb is replaced by that verb's
CID (recursive content addressing, as in Unison).  Renaming a verb therefore
changes no CID; editing a verb's body changes its CID and the CID of every
verb that calls it, so versions are addressed, not overwritten.

REGISTER-VERB / DEFINE-VERB add or replace a verb by NAME.  FIND-VERB,
VERB-CID, VERB-HISTORY, VERB-REFERENCES and VERB-REFERRERS inspect the
registry; CALL-VERB runs a verb (its references are wired by CID).  The
per-object side — which verbs an object answers to — is an immutable FSET map
in MUD-OBJECT's VERBS slot (OBJECT-VERBS, OBJECT-SET-VERB, ...), holding
name -> CID; the code itself lives once in the registry.")

  (:export
   ;; registry
   #:verb-registry
   #:make-verb-registry
   #:ensure-verb-registry
   #:verb-count
   #:map-verbs

   ;; definitions
   #:verb-definition
   #:verb-definition-p
   #:verb-definition-cid
   #:verb-definition-name
   #:verb-definition-lambda-list
   #:verb-definition-body
   #:verb-definition-source
   #:verb-definition-docstring
   #:verb-definition-references
   #:verb-definition-unresolved-references
   #:verb-definition-created-at

   ;; defining / lookup
   #:define-verb
   #:register-verb
   #:find-verb
   #:verb-cid
   #:verb-names
   #:verb-history
   #:verb-references
   #:verb-referrers
   #:verb-source
   #:verb-docstring
   #:verb-unresolved-references

   ;; invocation
   #:*verb-registry*
   #:verb-function
   #:call-verb

   ;; object integration
   #:object-define-verb!
   #:object-bind-verb!
   #:object-verb
   #:object-call-verb

   ;; serialization (store the registry as plain data)
   #:verb-registry->map
   #:map->verb-registry

   ;; persisting a world's registry in its CONFIG map
   #:*verb-registry-config-key*
   #:save-verb-registry!
   #:load-verb-registry!))
