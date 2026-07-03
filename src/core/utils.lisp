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
  "Log an informational message.
Writes to the console when *DEBUG-MODE* is non-NIL, and also issues a
Deeds info-event so that file-logging and other handlers can pick it up."
  (let ((message (apply #'format-message format-string args)))
    (when apeiron.core:*debug-mode*
      (format t "[INFO] ~A~%" message))
    (apeiron.core:issue-info-event message)
    nil))

(defun log-error (format-string &rest args)
  "Log an error message.
Writes to the console and also issues a Deeds error-event so that
file-logging and other handlers can pick it up."
  (let ((message (apply #'format-message format-string args)))
    (format t "[ERROR] ~A~%" message)
    (apeiron.core:issue-error-event message)
    nil))
