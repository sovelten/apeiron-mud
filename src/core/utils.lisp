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
  "Log an informational message."
  (when apeiron.core:*debug-mode*
    (format t "[INFO] ~A~%" (apply #'format-message format-string args)))
  nil)

(defun log-error (format-string &rest args)
  "Log an error message."
  (format t "[ERROR] ~A~%" (apply #'format-message format-string args))
  nil)
