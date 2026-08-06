;;;; run-docs.lisp — regenerate the Apeiron HTML documentation.
;;;;
;;;; Usage: sbcl --load run-docs.lisp
;;;;
;;;; Loads the docs-only system (apeiron-docs), which pulls in
;;;; 40ANTS-DOC and its renderer, then writes the HTML manual into
;;;; docs/.

(unless (find-package :quicklisp)
  (load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))

(push #p"./" asdf:*central-registry*)

;; Explicitly load the ASDF system definitions
(asdf:load-asd #P"./apeiron.asd")
(asdf:load-asd #P"./apeiron-docs.asd")

;; Load log4cl first and silence its default console (as run-tests.lisp does).
(ql:quickload :log4cl)
(log:config :fatal :sane :filter :fatal :immediate-flush)

;; Load the docs system — the only place the heavy renderer is loaded.
(ql:quickload :apeiron-docs)

;; Generate the HTML manual into docs/.
(apeiron.docs:generate-docs)
(format t "~%=== Documentation written to docs/ ===~%~%")

;; Exit cleanly
(sb-ext:exit :code 0)
