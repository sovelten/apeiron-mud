;;;; src/core/constants.lisp — Shared constants for the MUD core
;;;;
;;;; These are used by the core game logic and shared across all modules.
;;;; Server-specific configuration (ports, TLS, etc.) lives in the server
;;;; module's constants.lisp.

(in-package #:apeiron.core)

(defparameter *mud-version* "0.0.1")
(defparameter *debug-mode* t)

;; Object type constants
(defconstant +object-type-generic+   'generic)
(defconstant +object-type-room+      'room)
(defconstant +object-type-character+ 'character)
(defconstant +object-type-item+      'item)

;; Command constants
(defconstant +max-command-length+ 256)
(defconstant +command-timeout+    30)
