(defpackage #:mud-test
  (:use #:cl #:fiveam)
  (:export #:run-tests #:mud-tests
           #:setup-test-environment
           #:teardown-test-environment))

(in-package #:mud-test)

(def-suite mud-tests :description "Tests for the MUD server")

;; Ensure test isolation even when FiveAM's RUN is called directly
;; (e.g. via MCP test runner) without going through RUN-TESTS.
;; Silence BKNR progress output (writes to *trace-output*) and
;; point store directories at temporary paths.
(eval-when (:load-toplevel :execute)
  (setf mud:*debug-mode* nil)
  (setf bknr.datastore::*store-verbose* nil)
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    ;; Clean any leftover data from previous test runs so that
    ;; individual tests run directly (e.g. via MCP test runner)
    ;; start with a fresh slate without going through run-tests.
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (ensure-directories-exist temp-dir)
    (ensure-directories-exist data-dir)
    (setf mud::*store-directory* temp-dir)
    (setf mud::*data-directory* data-dir)))

;; Ensure test isolation even when FiveAM's RUN is called directly
;; (e.g. via MCP test runner) without going through RUN-TESTS.
;; Also disable debug-mode to prevent BROKEN-PIPE from log-message
;; writing to the worker's actual stdout fd-stream.

(defun setup-test-environment ()
  "Set up a clean, isolated temporary BKNR store for test runs.
Also closes any open store from a previous run and resets debug mode."
  (setf mud:*debug-mode* nil)
  (setf bknr.datastore::*store-verbose* nil)
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    ;; Close any open store from prior runs
    (when (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
      (ignore-errors (bknr.datastore:close-store))
      (makunbound 'bknr.datastore:*store*))
    ;; Clean previous test data
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (ensure-directories-exist temp-dir)
    (ensure-directories-exist data-dir)
    (setf mud::*store-directory* temp-dir)
    (setf mud::*data-directory* data-dir)
    (format t "~&Test store directory: ~A~%" temp-dir)
    (format t "~&Test data directory: ~A~%" data-dir)))

(defun teardown-test-environment ()
  "Clean up temporary test directories and close any open store."
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    ;; Close any open store
    (when (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
      (ignore-errors (bknr.datastore:close-store))
      (makunbound 'bknr.datastore:*store*))
    ;; Clean up temp dirs
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (setf mud:*debug-mode* nil)
    (setf bknr.datastore::*store-verbose* nil)))

(defun run-tests ()
  "Run all MUD tests with a clean, isolated temporary BKNR store.
Uses Fiveam's RUN (not RUN!) to avoid BROKEN-PIPE in subprocess contexts."
  (setup-test-environment)
  (unwind-protect
       (let ((*trace-output* (make-broadcast-stream))
             (results (run 'mud-tests)))
         ;; Count results using dynamic class resolution to avoid
         ;; package-lock issues with FiveAM internal symbols.
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
