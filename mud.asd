(defsystem "mud"
  :version "0.0.1"
  :description "A MUD server written in Common Lisp, inspired by DGD and LMUD"
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("usocket"
               "bordeaux-threads"
               "str"
               "cl-prevalence")
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "constants" :depends-on ("package"))
                 (:file "utils" :depends-on ("constants"))
                 (:file "session" :depends-on ("utils"))
                 (:file "object" :depends-on ("utils"))
                 (:file "room" :depends-on ("object"))
                 (:file "character" :depends-on ("object" "session"))
                 (:file "world" :depends-on ("character" "room"))
                 (:file "command-handler" :depends-on ("world"))
                 (:file "network" :depends-on ("command-handler"))))))
