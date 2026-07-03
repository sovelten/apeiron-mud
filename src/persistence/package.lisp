;;;; src/persistence/package.lisp — Package definition for the persistence module

;;;; src/persistence/package.lisp — Package definition for the persistence module

;;;; src/persistence/package.lisp — Package definition for the persistence module

;;;; src/persistence/package.lisp — Package definition for the persistence module

(defpackage #:apeiron.persistence
  (:use #:cl
        #:apeiron.core
        #:apeiron.core.utils)
  (:export
   ;; Metaclass
   #:wrapping-persistent-class
   #:defwrapping-persistent-class

   ;; Persistent classes
   #:persistent-object
   #:persistent-room
   #:persistent-guestbook
   #:persistent-world

   ;; Persistent factory functions
   #:new-persistent-object
   #:new-persistent-room
   #:new-persistent-guestbook

   ;; Store lifecycle
   #:*store-directory*
   #:open-mud-store
   #:sync-world

   ;; World persistence
   #:initial-world
   #:world-restore-or-initialize
   #:get-persistent-world))
