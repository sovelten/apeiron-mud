(in-package #:apeiron.core.utils)

(defvar *id-counter* 0)
(defvar *id-lock* (bordeaux-threads:make-lock "id-lock"))

(defun make-id ()
  "Generate a unique ID for objects."
  (bordeaux-threads:with-lock-held (*id-lock*)
    (incf *id-counter*)))

(defun format-message (format-string &rest args)
  "Format a message with proper line breaks."
  (apply #'format nil format-string args))

(defun log-message (format-string &rest args)
  "Log an informational message via log4cl.
The message is routed through the configured log4cl appenders (file and
console, depending on `configure-logging`).  All existing call sites
continue to work unchanged."
  (let ((message (apply #'format nil format-string args)))
    (log:info "~A" message))
  nil)

(defun log-error (format-string &rest args)
  "Log an error message via log4cl.
The message is routed through the configured log4cl appenders and always
printed to the console for visibility."
  (let ((message (apply #'format nil format-string args)))
    ;; Always print errors to stderr so they are visible even if
    ;; log4cl console appender is not configured.
    (format *error-output* "[ERROR] ~A~%" message)
    (log:error "~A" message))
  nil)
