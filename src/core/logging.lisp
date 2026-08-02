;;;; src/core/logging.lisp — Centralized log4cl configuration for the Apeiron MUD
;;;;
;;;; Provides `configure-logging` which sets up log4cl based on *RUN-MODE*:
;;;;   :PROD  — file + console at :INFO
;;;;   :DEBUG — file + console at :DEBUG
;;;;   :TEST  — file-only at :INFO, no console output
;;;;
;;;; A daily-rolling file appender writes to <data-directory>/mud.log
;;;; (old logs renamed to mud.log.YYYYMMDD).  NDC context from
;;;; LOG:WITH-NDC is included in the pattern layout.
;;;;
;;;; Call `configure-logging` once at server startup.
;;;; Call `shutdown-logging` at server stop.

(in-package #:apeiron.core)

(defvar *logging-configured* nil
  "T if `configure-logging` has already been called.")

(defun configure-logging (&key (log-directory *data-directory*))
  "Initialise log4cl for the MUD.

LOG-DIRECTORY is the directory where log files are written; defaults to
*DATA-DIRECTORY*.  Configuration is idempotent.

Behaviour is driven by *RUN-MODE*:
  :PROD  — file + console at :INFO
  :DEBUG — file + console at :DEBUG
  :TEST  — file-only at :INFO"
  (when *logging-configured*
    (log:info "Logging already configured; skipping re-initialisation.")
    (return-from configure-logging t))

  (ensure-directories-exist
   (merge-pathnames "mud.log" log-directory))

  (let* ((log-file (merge-pathnames "mud.log" log-directory))
         (level (ecase *run-mode* (:debug :debug) ((:prod :test) :info)))
         (console? (ecase *run-mode* ((:prod :debug) t) (:test nil))))

    ;; ── Clean slate, console locked at FATAL ────────────────────────────
    (log:config :fatal :sane :filter :fatal :immediate-flush)

    ;; ── Daily-rolling file appender ─────────────────────────────────────
    (log:config level
                :daily log-file
                :ndc
                :immediate-flush)

    ;; ── Console appender ─────────────────────────────────────────────────
    (when console?
      (log:config :console))

    (setf *logging-configured* t)
    (let ((msg (format nil "Logging initialised (~(~A~)) — log file: ~A"
                       *run-mode* log-file)))
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
