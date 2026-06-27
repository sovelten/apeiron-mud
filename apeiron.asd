;;;;
;;;; mud.asd — ASDF system definitions for the Apeiron MUD
;;;;
;;;; The project is organised into four modules, each with its own system:
;;;;
;;;;   apeiron-core       — Game logic: world, characters, rooms, objects,
;;;;                         sessions (without telnet I/O).
;;;;   apeiron-telnet     — RFC 854 telnet protocol implementation (standalone).
;;;;   apeiron-persistence — BKNR datastore persistence layer.
;;;;   apeiron-server     — Server that wires telnet I/O, persistence, and
;;;;                         game logic together.
;;;;
;;;; One convenience alias is provided:
;;;;   apeiron            — depends on all four modules above.

(defsystem "apeiron-core"
  :version "0.0.1"
  :description "Core game logic for the Apeiron MUD — world, characters, and their dependencies."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("usocket"
               "bordeaux-threads"
               "flexi-streams"
               "str"
               "cl-csv")
  :components ((:module "src/core"
                :components
                ((:file "package")
                 (:file "constants" :depends-on ("package"))
                 (:file "utils" :depends-on ("constants"))
                 (:file "object" :depends-on ("utils"))
                 (:file "room" :depends-on ("object"))
                 (:file "guestbook" :depends-on ("object"))
                 (:file "session" :depends-on ("utils"))
                 (:file "character" :depends-on ("object" "session"))
                 (:file "world" :depends-on ("room" "guestbook" "character"))))))

(defsystem "apeiron-telnet"
  :version "0.0.1"
  :description "Standalone RFC 854 Telnet protocol implementation."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("usocket"
               "flexi-streams"
               "bordeaux-threads"
               "cl+ssl")
  :components ((:module "src/telnet"
                :components
                ((:file "package")
                 (:file "protocol" :depends-on ("package"))
                 (:file "connection" :depends-on ("package" "protocol"))
                 (:file "tls" :depends-on ("package" "protocol" "connection"))))))

(defsystem "apeiron-persistence"
  :version "0.0.1"
  :description "BKNR datastore persistence layer for the Apeiron MUD."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron-core"
               "bknr.datastore"
               "bknr.indices"
               "bknr.utils")
  :components ((:module "src/persistence"
                :components
                ((:file "store")
                 (:file "persistent-world" :depends-on ("store"))))))

(defsystem "apeiron-server"
  :version "0.0.1"
  :description "MUD server — wires telnet I/O, persistence, and game logic together."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron-core"
               "apeiron-persistence"
               "apeiron-telnet"
               "usocket"
               "bordeaux-threads")
  :components ((:module "src/server"
                :components
                ((:file "session-telnet")
                 (:file "command-handler" :depends-on ("session-telnet"))
                 (:file "network" :depends-on ("command-handler"))))))

;; Convenience meta-system — loads everything
(defsystem "apeiron"
  :version "0.0.1"
  :description "Apeiron MUD — a MUD server written in Common Lisp, inspired by DGD and LMUD."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron-core"
               "apeiron-telnet"
               "apeiron-persistence"
               "apeiron-server"))

;; Backward-compatible alias
