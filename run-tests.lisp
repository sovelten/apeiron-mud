(unless (find-package :quicklisp)
  (load "/home/sophia/.quicklisp/setup.lisp"))

(push #p"./" asdf:*central-registry*)

;; Explicitly load the ASDF system definitions
(asdf:load-asd #P"./mud.asd")
(asdf:load-asd #P"./mud-test.asd")
(ql:quickload :mud)

;; Now load the tests
(ql:quickload :mud-test)

;; Run the tests
(format t "~%=== Running MUD Tests ===~%~%")
(mud.tests:run-tests)
(format t "~%=== Tests Complete ===~%~%")

;; Exit cleanly
(sb-ext:exit :code 0)
