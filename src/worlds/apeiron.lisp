;;;; src/worlds/apeiron.lisp — System entry point for the apeiron-worlds module
;;;;
;;;; This file is loaded first by ASDF.  The world-area definitions live in
;;;; world-areas.lisp so they can be loaded independently during development.

(in-package #:apeiron.worlds)

;; ─── Data directory ─────────────────────────────────────────────────────────
;; Runtime data files (guestbook CSV, etc.) live here, separate from BKNR
;; snapshots which clutter the project root.
