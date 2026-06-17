(defsystem "mud"
  :version "0.0.1"
  :description "A MUD server written in Common Lisp, inspired by DGD and LMUD"
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("usocket"
               "bordeaux-threads"
               "str"
               "cl-prevalence"
               "bknr.datastore"
               "bknr.indices"
               "bknr.utils"
               "cl-csv")
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "constants" :depends-on ("package"))
                 (:file "utils" :depends-on ("constants"))
                 (:file "session" :depends-on ("utils"))
                 (:file "object" :depends-on ("utils"))
                 (:file "room" :depends-on ("object"))
                 (:file "guestbook" :depends-on ("object"))
                 (:file "character" :depends-on ("object" "session"))
                 (:file "store" :depends-on ("package"))
                 (:file "world" :depends-on ("room" "guestbook" "character"))
                 (:file "persistent-world" :depends-on ("store" "world" "room" "guestbook"))
                 (:file "command-handler" :depends-on ("persistent-world"))
                 (:file "network" :depends-on ("command-handler"))))))
