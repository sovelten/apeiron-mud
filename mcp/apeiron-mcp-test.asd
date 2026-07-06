;;;;
;;;; apeiron-mcp-test.asd — Test system for apeiron-mcp
;;;;
;;;; Tests the MCP server: ANSI stripping, JSON-RPC protocol,
;;;; and MUD client integration.

(defsystem "apeiron-mcp-test"
  :version "0.1.0"
  :description "Tests for the apeiron-mcp MCP server."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron-mcp"
               "apeiron"
               "fiveam"
               "uiop"
               "yason")
  :components ((:module "tests"
                :components
                ((:file "test-package")
                 (:file "test-mcp" :depends-on ("test-package")))))
  :perform (test-op :after (op c)
             (declare (ignore op c))
             (funcall (find-symbol "RUN-TESTS" :apeiron-mcp-test))))
