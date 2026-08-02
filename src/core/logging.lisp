;;;; src/core/logging.lisp — Centralized log4cl configuration for the Apeiron MUD
;;;;
;;;; Provides `configure-logging` which sets up log4cl with:
;;;;   • A daily-rolling file appender to <data-directory>/mud.log
;;;;     (old logs renamed to mud.log.YYYYMMDD).
;;;;   • A console appender for development (when *DEBUG-MODE* is non-NIL).
;;;;   • Hierarchical loggers (apeiron.server, apeiron.core, apeiron.persistence).
;;;;
;;;; NDC (Nested Diagnostic Context) can be pushed via LOG:WITH-NDC inside
;;;; session handler threads so every log line from a connection automatically
;;;; carries its remote address and session metadata.  The :NDC layout option
;;;; ensures it appears in the log output.
;;;;
;;;; Call `configure-logging` once at server startup (replaces the old
;;;; `start-event-logging`).  Call `shutdown-logging` at server stop.

(in-package #:apeiron.core)

(defvar *logging-configured* nil
  "T if `configure-logging` has already been called.")

(defun configure-logging (&key (log-directory *data-directory*))
  "Initialise log4cl for the MUD.

LOG-DIRECTORY is the directory where log files are written; defaults to
*DATA-DIRECTORY*.  Configuration is idempotent — a second call is a no-op.

Sets up:
  • Root logger at :INFO level.
  • A daily-rolling file appender → <log-directory>/mud.log
    (rolled daily; old logs kept as mud.log.YYYYMMDD).
  • NDC context in the pattern layout so LOG:WITH-NDC data is visible.
  • A console appender when *DEBUG-MODE* is on.
  • Sub-loggers for each module so they can be independently tuned."
  (when *logging-configured*
    (log:info "Logging already configured; skipping re-initialisation.")
    (return-from configure-logging t))

  ;; Ensure log directory exists.
  (ensure-directories-exist
   (merge-pathnames "mud.log" log-directory))

  (let ((log-file (merge-pathnames "mud.log" log-directory)))
    ;; ── Root logger level + daily-rolling file appender ────────────────
    ;; Rolls daily; old logs stored as mud.log.YYYYMMDD.
    ;; :NDC includes Nested Diagnostic Context in the log pattern.
    (log:config :info
                :daily log-file
                :ndc
                :immediate-flush)

    ;; ── Console appender (debug mode) ──────────────────────────────────
    (when *debug-mode*
      (log:config :console))

    (setf *logging-configured* t)
    (let ((msg (format nil "Logging initialised — log file: ~A" log-file)))
      (log:info "~A" msg))
    t))

(defun shutdown-logging ()
  "Shut down log4cl, flushing any buffered messages.
Called from `stop-mud-server`."
  (when *logging-configured*
    (log:info "Logging shutting down.")
    ;; Reset to a sane minimal config so we don't leave file handles open.
    (log:config :sane)
    (setf *logging-configured* nil))
  (values))
