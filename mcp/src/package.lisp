(defpackage #:apeiron-mcp/src/package
  (:use #:cl)
  (:export
   ;; Connection state
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
