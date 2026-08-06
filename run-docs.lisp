;;;; run-docs.lisp — regenerate the Apeiron documentation.
;;;;
;;;; Usage: sbcl --load run-docs.lisp
;;;;
;;;; Uses the same 40ANTS-DOC docs-builder as the GitHub Action
;;;; (40ants/build-docs@v1): writes the HTML manual into docs/build/
;;;; and regenerates README.md from the @readme section.

(unless (find-package :quicklisp)
  (load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))

(push #p"./" asdf:*central-registry*)

;; Explicitly load the ASDF system definitions
(asdf:load-asd #P"./apeiron.asd")
(asdf:load-asd #P"./apeiron-docs.asd")

;; Load log4cl first and silence its default console (as run-tests.lisp does).
(ql:quickload :log4cl)
(log:config :fatal :sane :filter :fatal :immediate-flush)

;; The docs system — the only place the heavy renderer is loaded.
(ql:quickload :apeiron-docs)

;; The builder (same one the GitHub Action runs).
(ql:quickload :docs-builder)

;; Build the HTML manual (docs/build/) and the landing README.md.
;; error-on-warnings matches the GitHub Action (the warnings are the
;; "uppercase word looks like a symbol" lint — cosmetic).
(docs-builder:build :apeiron-docs :error-on-warnings nil)
(format t "~%=== Documentation written to docs/build/ and README.md ===~%~%")

;; Exit cleanly
(sb-ext:exit :code 0)
