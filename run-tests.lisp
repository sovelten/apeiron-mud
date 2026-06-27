(unless (find-package :quicklisp)
  (load "/home/sophia/.quicklisp/setup.lisp"))

(push #p"./" asdf:*central-registry*)

;; Explicitly load the ASDF system definitions
(asdf:load-asd #P"./apeiron.asd")
(asdf:load-asd #P"./apeiron-test.asd")
(ql:quickload :apeiron)

;; Now load the tests
(ql:quickload :apeiron-test)

;; Run the tests
(format t "~%=== Running Apeiron Tests ===~%~%")
(apeiron-test:run-tests)
(format t "~%=== Tests Complete ===~%~%")

;; Exit cleanly
(sb-ext:exit :code 0)
