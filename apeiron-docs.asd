;;;; apeiron-docs.asd — documentation system for the Apeiron MUD.
;;;;
;;;; Generates a full HTML manual with 40ANTS-DOC via the docs-builder
;;;; (run `sbcl --load run-docs.lisp` locally, or the
;;;; `40ants/build-docs@v1` GitHub Action in CI). The renderer
;;;; (40ants-doc-full and its heavy dependencies: 3bmd, common-doc,
;;;; spinneret, swank, ...) plus the autodoc machinery are loaded ONLY
;;;; here — never by the main apeiron systems. The main systems depend
;;;; only on the light 40ants-doc core to compile the embedded
;;;; DEFSECTION forms in the source.
;;;;
;;;; The direct "40ants-doc" dependency (as well as the package name
;;;; "apeiron-docs") lets the docs-builder's guesser recognise this
;;;; system; :homepage is used as the base URL for cross-links and
;;;; :source-control for "view source" links.

(defsystem "apeiron-docs"
  :version "0.0.1"
  :description "HTML documentation for the Apeiron MUD, generated with 40ANTS-DOC."
  :author "Sophia Velten"
  :license "MIT"
  :homepage "https://sovelten.github.io/apeiron-mud/"
  :source-control (:git "https://github.com/sovelten/apeiron-mud")
  :depends-on ("apeiron"
               "40ants-doc"
               "40ants-doc-full"
               "40ants-doc/autodoc")
  :components ((:module "docs"
                :components ((:file "apeiron-docs")))))
