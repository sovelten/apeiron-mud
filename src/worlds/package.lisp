;;;; src/worlds/package.lisp — Package definition for transient world builders

(defpackage #:apeiron.worlds
  (:use #:cl
        #:apeiron.core)
  (:import-from #:40ants-doc
                #:defsection
                #:section)
  (:import-from #:pythonic-string-reader
                #:pythonic-string-syntax)
  (:export
   ;; World definition entry point
   #:new-default-world
   ;; Decorator object
   #:mud-decorator
   #:new-decorator))
