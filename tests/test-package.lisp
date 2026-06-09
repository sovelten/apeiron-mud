(defpackage #:mud.tests
  (:use #:cl #:fiveam)
  (:export #:run-tests #:mud-tests))

(in-package #:mud.tests)

(def-suite mud-tests :description "Tests for the MUD server")

(defun run-tests ()
  "Run all MUD tests with a clean, isolated temporary prevalence location."
  (let* ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-prevalence/"))
         (mud::*system-location* temp-dir))
    (unwind-protect
         (progn
           ;; Ensure we clear any pre-existing temp directory
           (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
           (run! 'mud-tests))
      ;; Clean up the temporary directory after the tests finish
      (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore))))
