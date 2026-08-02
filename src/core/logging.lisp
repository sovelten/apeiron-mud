;;;; src/core/logging.lisp — Centralized log4cl configuration for the Apeiron MUD
;;;;
;;;; Provides `configure-logging` which sets up log4cl with:
;;;;   • A daily-rolling file appender to <data-directory>/mud.log
;;;;     (old logs renamed to mud.log.YYYYMMDD).
;;;;   • Console output controlled by the APEIRON_ENV environment variable.
;;;;
;;;; Environment-driven behaviour:
;;;;   APEIRON_ENV=test   → file-only at :INFO, console stays silent
;;;;   APEIRON_ENV=debug  → file + console at :DEBUG
;;;;   (unset/other)      → file + console at :INFO  (production default)
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

Reads the APEIRON_ENV environment variable to decide console behaviour:
  \"test\"  → file-only logging (console stays silent)
  \"debug\" → file + console at :DEBUG level
  (unset)  → file + console at :INFO level (production)

Sets up a daily-rolling file appender with NDC context in the pattern
layout so LOG:WITH-NDC data is visible in log output."
  (when *logging-configured*
    (log:info "Logging already configured; skipping re-initialisation.")
    (return-from configure-logging t))

  ;; Ensure log directory exists.
  (ensure-directories-exist
   (merge-pathnames "mud.log" log-directory))

  (let* ((apeiron-env (uiop:getenv "APEIRON_ENV"))
         (env (when apeiron-env (string-downcase (string-trim " " apeiron-env))))
         (log-level (if (string= env "debug") :debug :info))
         (log-file (merge-pathnames "mud.log" log-directory)))

    ;; ── Clean slate ────────────────────────────────────────────────────
    ;; :SANE clears all existing appenders.  :FATAL sets both the logger
    ;; level and, via :FILTER :FATAL, the console appender threshold so
    ;; that only FATAL messages reach the console.  This keeps the console
    ;; silent during tests and normal operation alike.
    (log:config :fatal :sane :filter :fatal :immediate-flush)

    ;; ── Daily-rolling file appender ────────────────────────────────────
    ;; Always active.  Rolls daily; old logs stored as mud.log.YYYYMMDD.
    (log:config log-level
                :daily log-file
                :ndc
                :immediate-flush)

    ;; ── Console appender ───────────────────────────────────────────────
    ;; In "test" mode the console stays silent (locked at :FATAL above).
    ;; In every other mode we add a console appender at the chosen level.
    (unless (string= env "test")
      (log:config :console))

    (setf *logging-configured* t)
    (let ((msg (format nil "Logging initialised (~A) — log file: ~A"
                       (or env "production") log-file)))
      (log:info "~A" msg))
    t))

(defun shutdown-logging ()
  "Shut down log4cl, flushing any buffered messages.
Called from `stop-mud-server`."
  (when *logging-configured*
    (log:info "Logging shutting down.")
    (log:config :fatal :immediate-flush)
    (setf *logging-configured* nil))
  (values))
