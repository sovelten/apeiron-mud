(defpackage #:mud-test
  (:use #:cl #:fiveam
        #:apeiron.core
        #:apeiron.core.utils
        #:apeiron.persistence
        #:apeiron.server)
  (:export #:run-tests #:mud-tests
           #:setup-test-environment
           #:teardown-test-environment))

(in-package #:mud-test)

(def-suite mud-tests :description "Tests for the MUD server")

(eval-when (:load-toplevel :execute)
  (setf *debug-mode* nil)
  (setf bknr.datastore::*store-verbose* nil)
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (ensure-directories-exist temp-dir)
    (ensure-directories-exist data-dir)
    (setf *store-directory* temp-dir)
    (setf *data-directory* data-dir)))

(defun setup-test-environment ()
  "Set up a clean, isolated temporary BKNR store for test runs."
  (setf *debug-mode* nil)
  (setf bknr.datastore::*store-verbose* nil)
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    (when (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
      (ignore-errors (bknr.datastore:close-store))
      (makunbound 'bknr.datastore:*store*))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (ensure-directories-exist temp-dir)
    (ensure-directories-exist data-dir)
    (setf *store-directory* temp-dir)
    (setf *data-directory* data-dir)
    (format t "~&Test store directory: ~A~%" temp-dir)
    (format t "~&Test data directory: ~A~%" data-dir)))

(defun teardown-test-environment ()
  "Clean up temporary test directories and close any open store."
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    (when (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
      (ignore-errors (bknr.datastore:close-store))
      (makunbound 'bknr.datastore:*store*))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (setf *debug-mode* nil)
    (setf bknr.datastore::*store-verbose* nil)))

(defun run-tests ()
  "Run all MUD tests with a clean, isolated temporary BKNR store."
  (setup-test-environment)
  (unwind-protect
       (let ((*trace-output* (make-broadcast-stream))
             (results (run 'mud-tests)))
         (let* ((fiveam-pkg (find-package :fiveam))
                (passed-class (and fiveam-pkg
                                   (find-class (find-symbol "TEST-PASSED" fiveam-pkg) nil)))
                (failed-class (and fiveam-pkg
                                   (find-class (find-symbol "TEST-FAILURE" fiveam-pkg) nil)))
                (skipped-class (and fiveam-pkg
                                    (find-class (find-symbol "TEST-SKIPPED" fiveam-pkg) nil)))
                (passed 0) (failed 0) (pending 0))
           (dolist (r results)
             (cond
               ((and passed-class (typep r passed-class)) (incf passed))
               ((and failed-class (typep r failed-class)) (incf failed))
               ((and skipped-class (typep r skipped-class)) (incf pending))
               (t (incf passed))))
           (format t "~%=== Results: ~D passed, ~D failed, ~D pending ===~%"
                   passed failed pending)
           (values passed failed pending)))
    (teardown-test-environment)))
