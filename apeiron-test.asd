(defsystem "apeiron-test"
  :version "0.0.1"
  :description "Tests for the Apeiron MUD server"
  :author "Sophia"
  :license "MIT"
  :depends-on ("apeiron" "fiveam")
  :components ((:module "tests"
                :components
                ((:file "test-package")
                 (:file "telnet/test-telnet" :depends-on ("test-package"))
                 (:file "core/test-object" :depends-on ("test-package"))
                 (:file "core/test-room" :depends-on ("test-package"))
                 (:file "core/test-guestbook" :depends-on ("test-package"))
                 (:file "core/test-character" :depends-on ("test-package"))
                 (:file "core/test-events" :depends-on ("test-package"))
                 (:file "core/test-world" :depends-on ("test-package"))
                 (:file "core/test-commands" :depends-on ("test-package"))
                 (:file "core/test-wordle" :depends-on ("test-package"))
                 (:file "persistence/test-persistent-world" :depends-on ("test-package"))
                 (:file "worlds/test-world-areas" :depends-on ("test-package"))
                 (:file "server/test-network" :depends-on ("test-package"))
                 (:file "server/test-integration" :depends-on ("test-package")))))
  :perform (test-op :after (op c)
             (declare (ignore op c))
             (funcall (find-symbol "RUN-TESTS" :apeiron-test))))
