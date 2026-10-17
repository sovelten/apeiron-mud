;;;; src/verbs/package.lisp — verb sugar over cl-cm-db
;;;;
;;;; The verb store itself is CL-CM-DB (content-addressable identities,
;;;; code, history, references and compiled functions).  This package adds
;;;; only the MUD-facing sugar: DEFINE-VERB / REGISTER-VERB, the docstring
;;;; convention, a world's database, and the per-object verb bindings.

(defpackage #:apeiron.verbs
  (:use #:cl
        #:apeiron.core)
  (:documentation
   "Verb sugar for the Apeiron MUD, on top of CL-CM-DB.

A *verb* is a named function whose identity is a content identifier (CID)
computed by CL-CM: its body is alpha-renamed (bound-variable names do not
matter) and every free reference to another verb is replaced by that verb's
CID (recursive content addressing, as in Unison).  Renaming a verb therefore
changes no CID; editing a verb's body changes its CID and the CID of every
verb that calls it, so versions are addressed, not overwritten.

A registry IS a CL-CM-DB:CODE-DATABASE.  Names, history, definitions,
references, referrers and compiled functions are all its responsibility; use
CL-CM-DB:IDENTITY-CID, DEFINITION-BY-IDENTITY, CODE-REFERENCES,
CODE-REFERRERS, IDENTITY-HISTORY, CODE-FUNCTION, CALL-IDENTITY, ... directly.
This package adds only:

  * DEFINE-VERB / REGISTER-VERB — lambda-list + body sugar, with the DEFUN
    docstring convention (VERB-DOCSTRING);
  * ENSURE-VERB-REGISTRY — opens a world's database;
  * the per-object side — which verbs an object answers to is an immutable
    FSET map in MUD-OBJECT's VERBS slot (OBJECT-VERBS, OBJECT-SET-VERB, ...),
    holding name -> CID, with OBJECT-DEFINE-VERB!, OBJECT-BIND-VERB!,
    OBJECT-VERB and OBJECT-CALL-VERB.")

  (:export
   ;; defining
   #:define-verb
   #:register-verb
   #:verb-docstring

   ;; a world's database
   #:ensure-verb-registry
   #:default-verb-database-directory

   ;; object integration
   #:object-define-verb!
   #:object-bind-verb!
   #:object-verb
   #:object-call-verb))
