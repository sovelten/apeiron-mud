;;;; mcp/src/package.lisp — Package definition for apeiron-mcp

(defpackage #:apeiron-mcp/src/package
  (:use #:cl)
  (:export
   ;; Connection state
   #:*mud-connection*
   #:mud-connected-p

   ;; MUD client
   #:connect-to-mud
   #:disconnect-from-mud
   #:send-command
   #:send-eval
   #:listen-for-activity
   #:strip-ansi
   #:connection-status

   ;; JSON-RPC processor (for tests & HTTP transport)
   #:%process-json-line
   #:%encode-json
   #:%parse-json
   #:%ensure-state
   #:%result
   #:%error
   #:%make-ht

   ;; HTTP server
   #:*http-acceptor*
   #:*http-port*
   #:http-server-running-p
   #:start-http-server
   #:stop-http-server
   ;; JSON-RPC / MCP server entry points
   #:main
   #:main-http

   ;; Constants
   #:+server-version+
   #:+server-name+))

(in-package #:apeiron-mcp/src/package)

(defparameter +server-name+ "apeiron-mcp"
  "Name reported to MCP clients during initialization.")

(defparameter +server-version+ "0.1.0"
  "Version reported to MCP clients during initialization.")

;; ─── Connection state ───────────────────────────────────────────

(defvar *mud-connection* nil
  "The current telnet connection to the MUD server, or NIL if not
connected.  Bound to a TELNET:TELNET-CONNECTION instance.")

(defun mud-connected-p ()
  "Return true when we have an active connection to the MUD."
  (and *mud-connection*
       (telnet:telnet-connection-alive-p *mud-connection*)))
