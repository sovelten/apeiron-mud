;;;; apeiron-docs.asd — documentation system for the Apeiron MUD.
;;;;
;;;; Generates a full HTML manual with 40ANTS-DOC. The renderer
;;;; (40ants-doc-full and its heavy dependencies: 3bmd, common-doc,
;;;; spinneret, swank, ...) plus the autodoc machinery are loaded ONLY
;;;; here — never by the main apeiron systems. The main systems depend
;;;; only on the light 40ants-doc core to compile the embedded
;;;; DEFSECTION forms in the source.
;;;;
;;;; Usage: sbcl --load run-docs.lisp

(defsystem "apeiron-docs"
  :version "0.0.1"
  :description "HTML documentation for the Apeiron MUD, generated with 40ANTS-DOC."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron"
               "40ants-doc-full"
               "40ants-doc/autodoc")
  :components ((:module "docs"
                :components ((:file "apeiron-docs")))))
