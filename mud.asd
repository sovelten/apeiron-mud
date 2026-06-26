(defsystem "mud"
  :version "0.0.1"
  :description "A MUD server written in Common Lisp, inspired by DGD and LMUD"
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("usocket"
               "bordeaux-threads"
               "flexi-streams"
               "str"
               "bknr.datastore"
               "bknr.indices"
               "bknr.utils"
               "cl-csv"
               "cl+ssl")
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "constants" :depends-on ("package"))
                 (:file "utils" :depends-on ("constants"))
                 (:module "telnet"
                  :components
                  ((:file "package")
                   (:file "protocol" :depends-on ("package"))
                   (:file "connection" :depends-on ("package" "protocol"))
                   (:file "tls" :depends-on ("package" "protocol" "connection"))))
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
