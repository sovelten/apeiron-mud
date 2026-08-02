;;;; src/core/logging.lisp — Centralized log4cl configuration for the Apeiron MUD
;;;;
;;;; Provides `configure-logging` which sets up log4cl with:
;;;;   • A daily-rolling file appender to <data-directory>/mud.log
;;;;     (old logs renamed to mud.log.YYYYMMDD).
;;;;   • Optional console output controlled by the APEIRON_ENV variable.
;;;;
;;;; Environment-driven behaviour:
;;;;   APEIRON_ENV=console → file + console at :INFO  (server with console)
;;;;   APEIRON_ENV=debug   → file + console at :DEBUG (development)
;;;;   (unset / "test")    → file-only at :INFO       (CI, tests, quiet)
;;;;
;;;; NDC (Nested Diagnostic Context) can be pushed via LOG:WITH-NDC inside
;;;; session handler threads so every log line from a connection automatically
;;;; carries its remote address and session metadata.  The :NDC layout option
;;;; ensures it appears in the log output.
;;;;
;;;; Call `configure-logging` once at server startup.
;;;; Call `shutdown-logging` at server stop.

(in-package #:apeiron.core)

(defvar *logging-configured* nil
  "T if `configure-logging` has already been called.")

(defun configure-logging (&key (log-directory *data-directory*))
  "Initialise log4cl for the MUD.

LOG-DIRECTORY is the directory where log files are written; defaults to
*DATA-DIRECTORY*.  Configuration is idempotent — a second call is a no-op.

Reads the APEIRON_ENV environment variable to decide console behaviour:
  \"console\" → file + console at :INFO (server)
  \"debug\"   → file + console at :DEBUG (development)
  (unset)    → file-only at :INFO (CI / tests / quiet production)

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
         (log-file (merge-pathnames "mud.log" log-directory))
         (console? (or (string= env "console") (string= env "debug"))))

    ;; ── Clean slate ────────────────────────────────────────────────────
    ;; :SANE :FATAL :FILTER :FATAL clears existing appenders and creates a
    ;; console appender locked at FATAL — silent by default.
    (log:config :fatal :sane :filter :fatal :immediate-flush)

    ;; ── Daily-rolling file appender ────────────────────────────────────
    ;; Always active.  Rolls daily; old logs stored as mud.log.YYYYMMDD.
    (log:config log-level
                :daily log-file
                :ndc
                :immediate-flush)

    ;; ── Console appender (opt-in) ──────────────────────────────────────
    (when console?
      (log:config :console))

    (setf *logging-configured* t)
    (let ((msg (format nil "Logging initialised (~A) — log file: ~A"
                       (or env "quiet") log-file)))
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
