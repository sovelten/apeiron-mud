(defsystem "mud-test"
  :version "0.0.1"
  :description "Tests for the MUD server"
  :author "Sophia"
  :license "MIT"
  :depends-on ("mud" "fiveam")
  :components ((:module "tests"
                :components
                ((:file "test-package")
                 (:file "test-object" :depends-on ("test-package"))
                 (:file "test-world" :depends-on ("test-package"))
                 (:file "test-player" :depends-on ("test-package"))
                 (:file "test-commands" :depends-on ("test-package"))
                 (:file "test-network" :depends-on ("test-package"))
                 (:file "test-integration" :depends-on ("test-package"))))))
