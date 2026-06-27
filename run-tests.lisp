(unless (find-package :quicklisp)
  (load "/home/sophia/.quicklisp/setup.lisp"))

(push #p"./" asdf:*central-registry*)

;; Explicitly load the ASDF system definitions
(asdf:load-asd #P"./apeiron.asd")
(asdf:load-asd #P"./mud-test.asd")
(ql:quickload :apeiron)

;; Now load the tests
(ql:quickload :mud-test)

;; Run the tests
(format t "~%=== Running MUD Tests ===~%~%")
(mud-test:run-tests)
(format t "~%=== Tests Complete ===~%~%")

;; Exit cleanly
(sb-ext:exit :code 0)
