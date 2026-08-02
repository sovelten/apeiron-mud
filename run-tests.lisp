(unless (find-package :quicklisp)
  (load "/home/sophia/.quicklisp/setup.lisp"))

(push #p"./" asdf:*central-registry*)

;; Explicitly load the ASDF system definitions
(asdf:load-asd #P"./apeiron.asd")
(asdf:load-asd #P"./apeiron-test.asd")

;; Set the environment so configure-logging picks "test" mode:
;; file-only logging, no console output.
(setf (uiop:getenv "APEIRON_ENV") "test")

;; Load log4cl first and silence its default console output before
;; anything else gets a chance to log.
(ql:quickload :log4cl)
(log:config :fatal :sane :filter :fatal :immediate-flush)

(ql:quickload :apeiron)

;; Now load the tests
(ql:quickload :apeiron-test)

;; Run the tests
(format t "~%=== Running Apeiron Tests ===~%~%")
(apeiron-test:run-tests)
(format t "~%=== Tests Complete ===~%~%")

;; Exit cleanly
(sb-ext:exit :code 0)
