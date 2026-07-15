;;;;
;;;; run-mcp.lisp — Start the apeiron-mcp MCP HTTP server
;;;;
;;;; Usage:
;;;;   sbcl --script run-mcp.lisp
;;;;
;;;; Starts the MCP HTTP server on 127.0.0.1:3001 and keeps it running.
;;;; Register in ~/.config/eca/config.json with:
;;;;
;;;;   "apeiron-mud": {"url": "http://127.0.0.1:3001/mcp"}

(require :asdf)

;; Register both systems with ASDF
(asdf:load-asd #P"~/apeiron-mud/apeiron.asd")
(asdf:load-asd #P"~/apeiron-mud/mcp/apeiron-mcp.asd")

;; Load the MCP system
(asdf:load-system :apeiron-mcp)

;; Start the HTTP server and keep the process alive
(apeiron-mcp/src/package:start-http-server :host "127.0.0.1" :port 3001)
(format *error-output* "~&apeiron-mcp: HTTP server on http://127.0.0.1:3001/mcp~%")
(format *error-output* "~&Press Ctrl-C to stop~%")
(finish-output *error-output*)

;; Block forever — Hunchentoot runs in background threads
(loop (sleep 60))
