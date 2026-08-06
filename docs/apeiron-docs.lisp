;;;; docs/apeiron-docs.lisp — Apeiron documentation manual.
;;;;
;;;; Built with 40ANTS-DOC (an MGL-PAX fork). Narrative sections live
;;;; next to the code they describe (src/core/world.lisp,
;;;; src/core/command-handler.lisp); this file ties them together and
;;;; adds an automatically generated API reference.
;;;;
;;;; FUTURE IDEA (flagged, not now): 40ANTS-DOC/AUTODOC discovers
;;;; packages using the package-inferred, slash-named convention
;;;; (foo/bar). Apeiron uses classic dot-named packages (apeiron.core),
;;;; so this file bridges that with DEFAUTODOC-PACKAGES. If the project
;;;; ever moves to package-inferred systems (package name = file path),
;;;; the built-in DEFAUTODOC macro can replace the bridge.

(defpackage #:apeiron.docs
  (:use #:cl #:40ants-doc)
  (:import-from #:pythonic-string-reader
                #:pythonic-string-syntax)
  (:export #:generate-docs
           #:@apeiron-manual))

(in-package #:apeiron.docs)

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

(defsection @apeiron-manual (:title "Apeiron Manual")
  """Apeiron is a MUD server written in Common Lisp. This manual is
  generated from the source code with 40ANTS-DOC: the narrative
  sections live next to the code that implements them, and the API
  reference is generated automatically from the exported symbols.

  ## Getting started

  Start the server and connect with a telnet client:

  ```
  sbcl --load run-mud.lisp
  telnet localhost 8888
  ```

  See README.md for a full quick start, the command reference and
  in-game tutorials."""
  (apeiron.core::@world section)
  (apeiron.core::@commands section)
  (@api section))

(defun generate-docs ()
  "Generate the HTML documentation into the `docs/` directory of the
  apeiron-docs system (the project's `docs/` folder)."
  (40ants-doc-full/builder:update-asdf-system-docs
   @apeiron-manual
   (asdf:find-system :apeiron-docs)))
