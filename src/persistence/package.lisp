;;;; src/persistence/package.lisp — Package definition for the persistence module

;;;; src/persistence/package.lisp — Package definition for the persistence module

;;;; src/persistence/package.lisp — Package definition for the persistence module

;;;; src/persistence/package.lisp — Package definition for the persistence module

(defpackage #:apeiron.persistence
  (:use #:cl
        #:apeiron.core
        #:apeiron.core.utils)
  ;; LIMB is referenced unqualified by persistent-world.lisp (the limb
  ;; migration).  Declaring it a shadowing import of APEIRON.CORE:LIMB
  ;; keeps the package's LIMB symbol identical to the core one even when
  ;; the packages are in flux during a hot reload, so the newly-exported
  ;; core symbol can never collide with a stray locally-interned LIMB.
  (:shadowing-import-from #:apeiron.core #:limb)
  (:import-from #:serapeum #:dict)
  (:export
   ;; Metaclass
   #:wrapping-persistent-class
   #:defwrapping-persistent-class

   ;; Declarative persistent class registry
   #:define-persistent-classes
   #:define-persistent-class
   #:*persistent-class-registry*
   #:transient->persistent-class
   #:world-register-persistent-class!

   ;; Persistent classes
   #:persistent-object
   #:persistent-room
   #:persistent-character
   #:persistent-guestbook
   #:persistent-wordle
   #:persistent-connection
   #:persistent-area
   #:persistent-world

   ;; Persistent factory functions
   #:new-persistent-object
   #:new-persistent-room
   #:new-persistent-guestbook

   ;; Store lifecycle
   #:*store-directory*
   #:open-mud-store
   #:safe-update
   #:sync-world

   ;; World persistence
   #:initial-world
   #:world-restore-or-initialize
   #:get-persistent-world
   #:materialize-object

   ;; Utilities
   #:refresh-guestbooks))
