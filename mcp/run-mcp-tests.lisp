(require :asdf)

;; Register both systems with ASDF
(asdf:load-asd #P"~/apeiron-mud/apeiron.asd")
(asdf:load-asd #P"~/apeiron-mud/mcp/apeiron-mcp.asd")
(asdf:load-asd #P"~/apeiron-mud/mcp/apeiron-mcp-test.asd")

;; Load the MCP systems (avoid double-load with quickload)
(asdf:load-system :apeiron-mcp)
(asdf:load-system :apeiron-mcp-test)

;; Run the tests
(format t "~%=== Running Apeiron MCP Server Tests ===~%~%")
(apeiron-mcp-test:run-tests)
(format t "~%=== Tests Complete ===~%~%")

;; Exit cleanly
(sb-ext:exit :code 0)
