;;;; src/core/constants.lisp — Shared constants for the MUD core
;;;;
;;;; These are used by the core game logic and shared across all modules.
;;;; Server-specific configuration (ports, TLS, etc.) lives in the server
;;;; module's constants.lisp.

(in-package #:apeiron.core)

(defparameter *mud-version* "0.0.1")
(defparameter *debug-mode* t)

;; Command constants
(defconstant +max-command-length+ 256)

;; ─── Run mode ────────────────────────────────────────────────────────────

(defvar *run-mode* :prod
  "One of :PROD, :DEBUG, or :TEST.  See logging.lisp for log behaviour.")

(defvar *data-directory*
  (merge-pathnames #p"data/" (asdf:system-source-directory :apeiron))
  "Directory for run-time data files (guestbook CSV, etc.).")
