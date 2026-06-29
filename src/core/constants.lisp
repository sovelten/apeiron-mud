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

;; ─── Runtime data directory ────────────────────────────────────────────────
;; Runtime data files (guestbook CSV, etc.) live here, separate from BKNR
;; snapshots which clutter the project root.

(defvar *data-directory*
  (merge-pathnames #p"data/" (asdf:system-source-directory :apeiron))
  "Directory for run-time data files (guestbook CSV, etc.).")
