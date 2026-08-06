;;;; docs/apeiron-docs.lisp — Apeiron documentation manual.
;;;;
;;;; Built with 40ANTS-DOC (an MGL-PAX fork). Narrative sections live
;;;; next to the code they describe (src/core/world.lisp,
;;;; src/core/command-handler.lisp); this file ties them together and
;;;; adds an automatically generated API reference.
;;;;
;;;; Conventions expected by the 40ANTS-DOC docs-builder (used by the
;;;; `40ants/build-docs` GitHub Action):
;;;;   - the package must be named like the ASDF system ("apeiron-docs");
;;;;   - the root manual section must be called `@index`;
;;;;   - a section named `@readme` becomes the generated README.md.
;;;;
;;;; DRY: @readme and @index reference the SAME content sections
;;;; (defined in docs/apeiron-manual.lisp) — the README is generated
;;;; from those sections too, so there is a single source of truth.
;;;;
;;;; FUTURE IDEA (flagged, not now): docs-builder discovers packages by
;;;; the package-inferred, slash-named convention (foo/bar). Apeiron
;;;; uses classic dot-named packages (apeiron.core), so this file
;;;; bridges that with DEFAUTODOC-PACKAGES. If the project ever moves
;;;; to package-inferred systems (package name = file path), the
;;;; built-in DEFAUTODOC macro can replace the bridge.

(defpackage #:apeiron-docs
  (:use #:cl #:40ants-doc)
  (:import-from #:pythonic-string-reader
                #:pythonic-string-syntax)
  (:import-from #:40ants-doc/locatives
                #:include)
  (:export #:@index
           #:@readme))

(in-package #:apeiron-docs)

(named-readtables:in-readtable pythonic-string-syntax)

(defmacro defautodoc-packages (name (&key packages (title "API")) &body prose)
  "Like 40ANTS-DOC/AUTODOC:DEFAUTODOC, but takes an explicit PACKAGES
  list (package designators) instead of discovering packages from an
  ASDF system name. Grouping into Classes / Generics / Functions /
  Macros / Types / Variables (including class readers and accessors)
  is done by 40ants-doc itself."
  (multiple-value-bind (subsections entries)
      (40ants-doc/autodoc::with-subsection-collector ()
        (loop for pkg in packages
              for package = (or (find-package pkg)
                                (error "Unknown package ~S" pkg))
              for section-name = (intern (format nil "@~A?PACKAGE"
                                                 (string-upcase (package-name package)))
                                         (symbol-package name))
              for package-section = (40ants-doc/autodoc::make-package-section
                                     section-name package)
              when package-section
                collect (list section-name 'section) into entries
                and do (40ants-doc/autodoc::register-subsection package-section)
              finally (return (values (40ants-doc/autodoc::registered-subsections)
                                      entries))))
    `(progn
       (defsection ,name (:title ,title)
         ,@prose
         ,@entries)
       ,@subsections)))

;;; Automatically generated API reference. Every exported symbol of the
;;; listed packages is classified and documented; nothing to maintain
;;; by hand — adding an export is enough to get it documented.
(defautodoc-packages @api (:packages (:apeiron.core :apeiron.core.utils)
                          :title "API Reference")
  "Automatically generated from the exported symbols of the
  `apeiron.core` package (and its small `apeiron.core.utils` helper
  package).")

;;; The landing README.md. All substantive content is REFERENCED from
;;; the shared sections in docs/apeiron-manual.lisp (single source of
;;; truth — the manual renders the same sections).
(defsection @readme (:title "Apeiron" :export t)
  """Apeiron is a MUD server written in Common Lisp, inspired by
  Dworkin's Game Driver (DGD) and LMUD, with the reckless capability of
  running Lisp code inside the game world.

  [![CI](https://github.com/sovelten/apeiron-mud/actions/workflows/test.yml/badge.svg)](https://github.com/sovelten/apeiron-mud/actions/workflows/test.yml)"""
  (@getting-started section)
  (@architecture section)
  (@protocols section)
  (@command-reference section)
  """## Documentation

  - Full manual (generated from the source with 40ANTS-DOC):
    https://sovelten.github.io/apeiron-mud/
  - Tutorial: create a secret room —
    [docs/tutorial-secret-room.md](https://github.com/sovelten/apeiron-mud/blob/main/docs/tutorial-secret-room.md)
  - Tutorial: Wordle puzzle game —
    [docs/tutorial-wordle.md](https://github.com/sovelten/apeiron-mud/blob/main/docs/tutorial-wordle.md)
  - MCP server (LLM integration):
    [mcp/README.md](https://github.com/sovelten/apeiron-mud/blob/main/mcp/README.md)""")

(defsection @index (:title "Apeiron Manual" :export t)
  """Apeiron is a MUD server written in Common Lisp. This manual is
  generated from the source code with 40ANTS-DOC: the narrative
  sections live next to the code that implements them, and the API
  reference is generated automatically from the exported symbols.

  See the README for a quick start and the command reference."""
  (@getting-started section)
  (@architecture section)
  (@protocols section)
  (@features section)
  (@development section)
  (@command-reference section)
  (apeiron.core::@world section)
  (apeiron.core::@commands section)
  (@tutorial-secret-room section)
  (@tutorial-wordle section)
  (@deployment section)
  (@troubleshooting section)
  (@dependencies section)
  (@mcp section)
  (@api section))
