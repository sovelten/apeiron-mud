;;;; src/core/colors.lisp — ANSI color support for MUD output
;;;;
;;;; ANSI escape codes for terminal coloring, with helper functions
;;;; to wrap text in colors.  Follows ECMA-48 / ITU-T T.416 standard
;;;; for Select Graphic Rendition (SGR) parameters.
;;;;
;;;; Reference: https://tintin.mudhalla.net/info/ansicolor/

(in-package #:apeiron.core)

;; ─── SGR (Select Graphic Rendition) parameter constants ─────────────────────
;; Each is a numeric code sent as CSI <params>m, e.g. ESC[31m for red.

;; Attributes
(defparameter +sgr-reset+        0 "Reset all attributes")
(defparameter +sgr-bold+         1 "Bold / increased intensity")
(defparameter +sgr-dim+          2 "Dim / decreased intensity")
(defparameter +sgr-italic+       3 "Italic (not widely supported)")
(defparameter +sgr-underline+    4 "Underline")
(defparameter +sgr-blink+        5 "Slow blink")
(defparameter +sgr-reverse+      7 "Reverse / inverse video")

;; Standard foreground colors (30–37)
(defparameter +sgr-fg-black+     30)
(defparameter +sgr-fg-red+       31)
(defparameter +sgr-fg-green+     32)
(defparameter +sgr-fg-yellow+    33)
(defparameter +sgr-fg-blue+      34)
(defparameter +sgr-fg-magenta+   35)
(defparameter +sgr-fg-cyan+      36)
(defparameter +sgr-fg-white+     37)

;; Standard background colors (40–47)
(defparameter +sgr-bg-black+     40)
(defparameter +sgr-bg-red+       41)
(defparameter +sgr-bg-green+     42)
(defparameter +sgr-bg-yellow+    43)
(defparameter +sgr-bg-blue+      44)
(defparameter +sgr-bg-magenta+   45)
(defparameter +sgr-bg-cyan+      46)
(defparameter +sgr-bg-white+     47)

;; Bright foreground colors (90–97)
(defparameter +sgr-fg-bright-black+   90)
(defparameter +sgr-fg-bright-red+     91)
(defparameter +sgr-fg-bright-green+   92)
(defparameter +sgr-fg-bright-yellow+  93)
(defparameter +sgr-fg-bright-blue+    94)
(defparameter +sgr-fg-bright-magenta+ 95)
(defparameter +sgr-fg-bright-cyan+    96)
(defparameter +sgr-fg-bright-white+   97)

;; Bright background colors (100–107)
(defparameter +sgr-bg-bright-black+   100)
(defparameter +sgr-bg-bright-red+     101)
(defparameter +sgr-bg-bright-green+   102)
(defparameter +sgr-bg-bright-yellow+  103)
(defparameter +sgr-bg-bright-blue+    104)
(defparameter +sgr-bg-bright-magenta+ 105)
(defparameter +sgr-bg-bright-cyan+    106)
(defparameter +sgr-bg-bright-white+   107)

;; ─── Escape sequence construction ───────────────────────────────────────────

(declaim (inline %csi %sgr))

;; ─── Dynamic control ────────────────────────────────────────────────────────

(defparameter *colorize* t
  "When non-NIL, color-text and helper functions emit ANSI escape codes.
Bind this to NIL to disable colors globally per-session or per-thread.")

(defun %csi ()
  "Return the Control Sequence Introducer: ESC ["
  (format nil "~C[" (code-char 27)))

(defun %sgr (&rest params)
  "Build a Select Graphic Rendition sequence from one or more numeric parameters.
Produces: ESC[<params>m"
  (format nil "~A~{~D~^;~}m" (%csi) params))

;; ─── Color application helpers ──────────────────────────────────────────────

(defun color-text (text &rest sgr-params)
  "Wrap TEXT in an ANSI SGR escape sequence.
SGR-PARAMS are integers (e.g. +SGR-FG-RED+, +SGR-BOLD+).
Always appends reset at the end.
Respects *COLORIZE* — returns plain TEXT when *COLORIZE* is NIL.

Examples:
  (color-text \"Red Alert!\" +sgr-fg-red+ +sgr-bold+)
  (color-text \"Green text\" +sgr-fg-green+)"
  (if *colorize*
      (format nil "~A~A~A" (apply #'%sgr sgr-params) text (%sgr +sgr-reset+))
      text))

(defun bold (text)
  "Wrap TEXT in ANSI bold."
  (color-text text +sgr-bold+))

(defun underline (text)
  "Wrap TEXT in ANSI underline."
  (color-text text +sgr-underline+))

(defun red (text)
  "Wrap TEXT in ANSI red foreground."
  (color-text text +sgr-fg-red+))

(defun green (text)
  "Wrap TEXT in ANSI green foreground."
  (color-text text +sgr-fg-green+))

(defun yellow (text)
  "Wrap TEXT in ANSI yellow foreground."
  (color-text text +sgr-fg-yellow+))

(defun blue (text)
  "Wrap TEXT in ANSI blue foreground."
  (color-text text +sgr-fg-blue+))

(defun magenta (text)
  "Wrap TEXT in ANSI magenta foreground."
  (color-text text +sgr-fg-magenta+))

(defun cyan (text)
  "Wrap TEXT in ANSI cyan foreground."
  (color-text text +sgr-fg-cyan+))

(defun white (text)
  "Wrap TEXT in ANSI white foreground."
  (color-text text +sgr-fg-white+))

(defun bright-red (text)
  "Wrap TEXT in ANSI bright red foreground."
  (color-text text +sgr-fg-bright-red+))

(defun bright-green (text)
  "Wrap TEXT in ANSI bright green foreground."
  (color-text text +sgr-fg-bright-green+))

(defun bright-yellow (text)
  "Wrap TEXT in ANSI bright yellow foreground."
  (color-text text +sgr-fg-bright-yellow+))

(defun bright-blue (text)
  "Wrap TEXT in ANSI bright blue foreground."
  (color-text text +sgr-fg-bright-blue+))

(defun bright-magenta (text)
  "Wrap TEXT in ANSI bright magenta foreground."
  (color-text text +sgr-fg-bright-magenta+))

(defun bright-cyan (text)
  "Wrap TEXT in ANSI bright cyan foreground."
  (color-text text +sgr-fg-bright-cyan+))

(defun bright-white (text)
  "Wrap TEXT in ANSI bright white foreground."
  (color-text text +sgr-fg-bright-white+))

(defun bold-red (text)
  "Wrap TEXT in ANSI bold + red foreground."
  (color-text text +sgr-bold+ +sgr-fg-red+))

(defun bold-green (text)
  "Wrap TEXT in ANSI bold + green foreground."
  (color-text text +sgr-bold+ +sgr-fg-green+))

(defun bold-yellow (text)
  "Wrap TEXT in ANSI bold + yellow foreground."
  (color-text text +sgr-bold+ +sgr-fg-yellow+))

(defun bold-cyan (text)
  "Wrap TEXT in ANSI bold + cyan foreground."
  (color-text text +sgr-bold+ +sgr-fg-cyan+))

(defun bold-white (text)
  "Wrap TEXT in ANSI bold + bright white foreground."
  (color-text text +sgr-bold+ +sgr-fg-bright-white+))
