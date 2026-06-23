(defsystem "mud-test"
  :version "0.0.1"
  :description "Tests for the MUD server"
  :author "Sophia"
  :license "MIT"
  :depends-on ("mud" "fiveam")
  :components ((:module "tests"
                :components
                ((:file "test-package")
                 (:file "test-telnet" :depends-on ("test-package"))
                 (:file "test-object" :depends-on ("test-package"))
                 (:file "test-room" :depends-on ("test-package"))
                 (:file "test-guestbook" :depends-on ("test-package"))
                 (:file "test-world" :depends-on ("test-package"))
                 (:file "test-character" :depends-on ("test-package"))
                 (:file "test-commands" :depends-on ("test-package"))
                 (:file "test-network" :depends-on ("test-package"))
                 (:file "test-integration" :depends-on ("test-package"))
                 (:file "test-persistent-world" :depends-on ("test-package")))))
  :perform (test-op :after (op c)
             (declare (ignore op c))
             (funcall (find-symbol "RUN-TESTS" :mud-test))))
