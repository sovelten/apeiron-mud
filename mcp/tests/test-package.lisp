;;;; mcp/tests/test-package.lisp — Package and test suites for apeiron-mcp

(defpackage #:apeiron-mcp-test
  (:use #:cl #:fiveam
        #:apeiron.core
        #:apeiron.persistence
        #:apeiron.server)
  (:import-from #:apeiron-mcp/src/package
                #:strip-ansi
                #:connect-to-mud
                #:disconnect-from-mud
                #:send-command
                #:send-eval
                #:connection-status
                #:mud-connected-p
                ;; HTTP server
                #:start-http-server
                #:stop-http-server
                #:http-server-running-p
                #:*http-port*
                ;; JSON helpers
                #:%parse-json)
  (:export #:run-tests
           #:mcp-suite))

(in-package #:apeiron-mcp-test)

;; ─── BKNR test isolation ───────────────────────────────────
;; Mirror what apeiron-test does: use temporary directories so
;; tests don't interfere with the main project's datastore.

(eval-when (:load-toplevel :execute)
  (setf *debug-mode* nil)
  (setf *colorize* nil)
  (setf bknr.datastore::*store-verbose* nil)
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mcp-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mcp-test-data/")))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (ensure-directories-exist temp-dir)
    (ensure-directories-exist data-dir)
    (setf *store-directory* temp-dir)
    (setf *data-directory* data-dir)))

(defun setup-test-environment ()
  "Set up a clean BKNR store for MCP test runs."
  (setf *debug-mode* nil)
  (setf *colorize* nil)
  (setf bknr.datastore::*store-verbose* nil)
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mcp-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mcp-test-data/")))
    (when (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
      (ignore-errors (bknr.datastore:close-store))
      (makunbound 'bknr.datastore:*store*))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (ensure-directories-exist temp-dir)
    (ensure-directories-exist data-dir)
    (setf *store-directory* temp-dir)
    (setf *data-directory* data-dir)))

(defun teardown-test-environment ()
  "Clean up temporary test directories and close any open store."
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mcp-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mcp-test-data/")))
    (when (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
      (ignore-errors (bknr.datastore:close-store))
      (makunbound 'bknr.datastore:*store*))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)))

;; ─── Suite definitions ──────────────────────────────────────

(def-suite mcp-suite
    :description "apeiron-mcp MCP server tests")

(def-suite ansi-suite
    :in mcp-suite
    :description "ANSI escape code stripping")

(def-suite protocol-suite
    :in mcp-suite
    :description "JSON-RPC 2.0 / MCP protocol handling")

(def-suite integration-suite
    :in mcp-suite
    :description "MUD client integration tests (requires MUD server)")

(def-suite http-suite
    :in mcp-suite
    :description "HTTP transport integration tests")

;; ─── Run helper ─────────────────────────────────────────────

(defun run-tests ()
  "Run all MCP tests with a clean BKNR test store."
  (setup-test-environment)
  (unwind-protect
       (let ((results (run 'mcp-suite)))
         (let* ((fiveam-pkg (find-package :fiveam))
                (passed-class (and fiveam-pkg
                                   (find-class (find-symbol "TEST-PASSED" fiveam-pkg) nil)))
                (failed-class (and fiveam-pkg
                                   (find-class (find-symbol "TEST-FAILURE" fiveam-pkg) nil)))
                (error-class  (and fiveam-pkg
                                   (find-class (find-symbol "TEST-ERROR" fiveam-pkg) nil)))
                (skipped-class (and fiveam-pkg
                                    (find-class (find-symbol "TEST-SKIPPED" fiveam-pkg) nil)))
                (passed 0) (failed 0) (errors 0) (pending 0))
           (dolist (r results)
             (cond
               ((and passed-class (typep r passed-class)) (incf passed))
               ((and error-class (typep r error-class))
                (incf errors)
                (format t "~&ERROR: ~A~%" (fiveam::test-name r))
                (handler-case
                    (let* ((cond-slot (find-symbol "CONDITION" fiveam-pkg))
                           (c (and cond-slot (slot-value r cond-slot))))
                      (when c (format t "  condition: ~A~%" c)))
                  (error () (format t "  (condition unavailable)~%"))))
               ((and failed-class (typep r failed-class)) (incf failed))
               ((and skipped-class (typep r skipped-class)) (incf pending))
               (t (incf passed))))
           (format t "~&=== MCP Results: ~D passed, ~D failed, ~D errors, ~D pending ===~%"
                   passed failed errors pending)
           (values passed failed pending)))
    (teardown-test-environment)))
