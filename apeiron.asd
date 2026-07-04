;;;;
;;;; apeiron.asd — ASDF system definitions for the Apeiron MUD
;;;;
;;;; The project is organised into four modules, each with its own system:
;;;;
;;;;   apeiron/core        — Game logic: world, characters, rooms, objects,
;;;;                          sessions (without telnet I/O).
;;;;   apeiron/telnet      — RFC 854 telnet protocol implementation (standalone).
;;;;   apeiron/persistence — BKNR datastore persistence layer.
;;;;   apeiron/server      — Server that wires telnet I/O, persistence, and
;;;;                          game logic together.
;;;;   apeiron/worlds      — Transient world definitions.
;;;;
;;;; One convenience alias is provided:
;;;;   apeiron             — depends on all five modules above.

(defsystem "apeiron/core"
  :version "0.0.1"
  :description "Core game logic for the Apeiron MUD — world, characters, and their dependencies."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("bordeaux-threads"
               "cl-csv"
               "deeds")
  :components ((:module "src/core"
                :components
                ((:file "package")
                 (:file "constants" :depends-on ("package"))
                 (:file "events" :depends-on ("package"))
                 (:file "utils" :depends-on ("constants" "events"))
                 (:file "colors" :depends-on ("package"))
                 (:file "object" :depends-on ("utils"))
                 (:file "container" :depends-on ("object"))
                 (:file "room" :depends-on ("object" "container"))
                 (:file "guestbook" :depends-on ("object"))
                 (:file "connection" :depends-on ("room"))
                 (:file "npc" :depends-on ("object"))
                 (:file "combat" :depends-on ("npc" "character"))
                 (:file "session" :depends-on ("utils"))
                 (:file "character" :depends-on ("object" "session" "container"))
                 (:file "command-handler" :depends-on ("session"))
                 (:file "world" :depends-on ("room" "connection" "guestbook" "character"))))))

(defsystem "apeiron/telnet"
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

(defsystem "apeiron/persistence"
  :version "0.0.1"
  :description "BKNR datastore persistence layer for the Apeiron MUD."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron/core"
               "bknr.datastore"
               "bknr.indices"
               "bknr.utils")
  :components ((:module "src/persistence"
                :components
                ((:file "package")
                 (:file "store")
                 (:file "persistent-world" :depends-on ("store"))))))

(defsystem "apeiron/worlds"
  :version "0.0.1"
  :description "Transient world definitions for the Apeiron MUD."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron/core")
  :components ((:module "src/worlds"
                :components
                ((:file "package")
                 (:file "apeiron" :depends-on ("package"))
                 (:file "world-areas" :depends-on ("apeiron"))))))

(defsystem "apeiron/server"
  :version "0.0.1"
  :description "MUD server — wires telnet I/O, persistence, and game logic together."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron/core"
               "apeiron/persistence"
               "apeiron/telnet"
               "usocket"
               "bordeaux-threads")
  :components ((:module "src/server"
                :components
                ((:file "package")
                 (:file "constants")
                 (:file "session-telnet")
                 (:file "network" :depends-on ("session-telnet"))))))

;; Convenience meta-system — loads everything
(defsystem "apeiron"
  :version "0.0.1"
  :description "Apeiron MUD — a MUD server written in Common Lisp, inspired by DGD and LMUD."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron/core"
               "apeiron/telnet"
               "apeiron/persistence"
               "apeiron/worlds"
               "apeiron/server"))
