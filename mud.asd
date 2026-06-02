(defsystem "mud"
  :version "0.0.1"
  :description "A MUD server written in Common Lisp, inspired by DGD and LMUD"
  :author "Sophia"
  :license "MIT"
  :depends-on ("usocket"
               "bordeaux-threads"
               "str")
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "constants" :depends-on ("package"))
                 (:file "utils" :depends-on ("package" "constants"))
                 (:file "object" :depends-on ("package" "constants" "utils"))
                 (:file "world" :depends-on ("package" "constants" "object"))
                 (:file "player" :depends-on ("package" "constants" "object" "world"))
                 (:file "command-handler" :depends-on ("package" "constants" "player" "world"))
                 (:file "network" :depends-on ("package" "constants" "player" "command-handler"))
                 (:file "server" :depends-on ("package" "constants" "network" "world"))))))
