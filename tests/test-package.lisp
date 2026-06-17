(defpackage #:mud-test
  (:use #:cl #:fiveam)
  (:export #:run-tests #:mud-tests))

(in-package #:mud-test)

(def-suite mud-tests :description "Tests for the MUD server")

(defun run-tests ()
  "Run all MUD tests with a clean, isolated temporary BKNR store."
  (let* ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
         (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/"))
         (mud::*store-directory* temp-dir)
         (mud::*data-directory* data-dir))
    (format t "~&Test store directory: ~A~%" temp-dir)
    (format t "~&Test data directory: ~A~%" data-dir)
    (unwind-protect
         (progn
           ;; Clean previous test data
           (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
           (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
           (ensure-directories-exist data-dir)
           (run! 'mud-tests))
      ;; Clean up after tests
      (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
      (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore))))
