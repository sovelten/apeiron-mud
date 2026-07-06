;;;; mcp/src/server.lisp — JSON-RPC 2.0 / MCP protocol over stdio
;;;;
;;;; Implements the Model Context Protocol (MCP) over standard I/O.
;;;; Reads newline-delimited JSON-RPC 2.0 requests from stdin and
;;;; writes responses to stdout.
;;;;
;;;; MCP lifecycle:
;;;;   1. Client sends initialize → we return server info + capabilities
;;;;   2. Client sends notifications/initialized → no response
;;;;   3. Client sends tools/list → we return all tool descriptors
;;;;   4. Client sends tools/call → we dispatch to tool handler
;;;;   5. ... repeat 3-4 until client disconnects
;;;;
;;;; Reference: https://spec.modelcontextprotocol.io/

(in-package #:apeiron-mcp/src/package)

;; Re-export from tools.lisp
;; (symbols are already in the package via package.lisp exports)

;; ─── Supported MCP protocol versions ────────────────────────────

(defparameter +supported-protocol-versions+
  '("2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05")
  "MCP protocol versions we support, ordered by preference.")

;; ─── Server state ───────────────────────────────────────────────

(defvar *server-state* nil
  "Hash-table holding mutable server state:
  :initialized-p  — T after a successful initialize handshake
  :client-info    — hash-table from initialize params
  :protocol-version — the negotiated protocol version string")

(defun %ensure-state (&optional (state *server-state*))
  "Initialize STATE (defaults to *SERVER-STATE*) if it hasn't been set yet.
Returns the state hash-table."
  (unless state
    (setf state (make-hash-table :test 'equal))
    (when (eq state *server-state*)
      (setf *server-state* state)))
  state)

;; ─── JSON encode/decode ─────────────────────────────────────────

(defun %parse-json (line)
  "Parse LINE as JSON, returning a hash-table or signaling an error."
  (yason:parse line))

(defun %encode-json (obj)
  "Encode OBJ as a JSON string."
  (with-output-to-string (stream)
    (yason:encode obj stream)))

;; ─── Initialize handler ─────────────────────────────────────────

(defun %handle-initialize (id params &optional (state *server-state*))
  "Handle the MCP initialize request.
Negotiates protocol version and returns server capabilities.
When STATE is provided, it is used instead of the global *SERVER-STATE*
(needed for HTTP sessions)."
  (let* ((state (%ensure-state state))
         (client-ver (and params (hash-table-p params)
                          (gethash "protocolVersion" params)))
         (chosen (if (and client-ver
                          (find client-ver +supported-protocol-versions+
                                :test #'string=))
                     client-ver
                     (first +supported-protocol-versions+))))
    ;; Record initialization
    (setf (gethash :initialized-p state) t)
    (setf (gethash :protocol-version state) chosen)
    (when (and params (hash-table-p params))
      (setf (gethash :client-info state)
            (gethash "clientInfo" params)))

    (%result id
             (%make-ht
              "protocolVersion" chosen
              "capabilities" (%make-ht
                              "tools" (%make-ht))
              "serverInfo" (%make-ht
                            "name" +server-name+
                            "version" +server-version+)))))

;; ─── Tools/list handler ─────────────────────────────────────────

(defun %handle-tools-list (id)
  "Return the list of available tools."
  (%result id (%make-ht "tools" (%get-tool-descriptors))))

;; ─── Tools/call handler ─────────────────────────────────────────

(defun %handle-tools-call (id params)
  "Dispatch a tool call to the registered handler."
  (let* ((name (and params (hash-table-p params)
                    (gethash "name" params)))
         (args (and params (hash-table-p params)
                    (gethash "arguments" params))))
    (unless name
      (return-from %handle-tools-call
        (%error id -32602 "Missing tool name")))
    (let ((handler (%get-tool-handler name)))
      (if handler
          (funcall handler id args)
          (%error id -32601
                  (format nil "Tool ~A not found. Available: mud-connect, mud-send, mud-eval, mud-disconnect, mud-status"
                          name))))))

;; ─── Request dispatch ───────────────────────────────────────────

(defun %handle-request (id method params &optional (state *server-state*))
  "Dispatch an incoming JSON-RPC request to the appropriate handler.
When STATE is provided, it is used instead of the global *SERVER-STATE*
(needed for HTTP sessions)."
  (cond
    ((string= method "initialize")
     (%handle-initialize id params state))
    ((string= method "tools/list")
     (%handle-tools-list id))
    ((string= method "tools/call")
     (%handle-tools-call id params))
    ((string= method "ping")
     (%result id (%make-ht)))
    (t
     (%error id -32601 (format nil "Method ~A not found" method)))))

(defun %handle-notification (method params)
  "Handle an incoming JSON-RPC notification (no response expected)."
  (declare (ignore params))
  (cond
    ((string= method "notifications/initialized")
     nil)
    (t nil)))

;; ─── Main JSON-RPC processor ────────────────────────────────────

(defun %process-json-line (line &optional (state *server-state*))
  "Process a single JSON-RPC line.  Returns a JSON response string,
or NIL for notifications (which require no response).
When STATE is provided, it is used instead of the global *SERVER-STATE*
(needed for HTTP sessions)."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) line)))
    (when (string= trimmed "")
      (return-from %process-json-line nil))

    ;; Parse the JSON
    (let ((msg (handler-case
                   (%parse-json trimmed)
                 (error (e)
                   (return-from %process-json-line
                     (%encode-json (%error nil -32700
                                          (format nil "Parse error: ~A" e))))))))
      (unless (hash-table-p msg)
        (return-from %process-json-line
          (%encode-json (%error nil -32600 "Invalid Request"))))

      (let ((jsonrpc (gethash "jsonrpc" msg))
            (id (gethash "id" msg))
            (method (gethash "method" msg))
            (params (gethash "params" msg)))

        (unless (and (stringp jsonrpc) (string= jsonrpc "2.0"))
          (return-from %process-json-line
            (%encode-json (%error id -32600 "Invalid Request: jsonrpc must be \"2.0\""))))

        (handler-case
            (cond
              ;; Request (has both method and id)
              ((and method id)
               (let ((response (%handle-request id method params state)))
                 (%encode-json response)))

              ;; Notification (has method, no id)
              (method
               (%handle-notification method params)
               nil)

              ;; Neither — invalid
              (t
               (%encode-json (%error id -32600 "Invalid Request: missing method"))))
          (error (e)
            (%encode-json (%error id -32603
                                 (format nil "Internal error: ~A" e)))))))))

;; ─── Main entry point ───────────────────────────────────────────

(defun main ()
  "Entry point for the apeiron-mcp MCP server.

Reads JSON-RPC 2.0 requests from *standard-input*, processes them,
and writes responses to *standard-output*.  Designed to be run as a
subprocess by an MCP client (Claude Desktop, Continue, etc.).

Usage (from command line):
  sbcl --load apeiron-mcp.asd --eval \"(apeiron-mcp/src/server:main)\"

Or when built as a standalone binary:
  ./apeiron-mcp"
  (%ensure-state)

  ;; Ensure stdout is unbuffered — responses must arrive immediately
  (setf *standard-output* (make-synonym-stream '*standard-output*))

  ;; Enter the JSON-RPC read-loop
  (handler-case
      (loop
        (let ((line (read-line *standard-input* nil :eof)))
          (when (eq line :eof)
            (return-from main))
          (let ((response (%process-json-line line)))
            (when response
              (write-line response *standard-output*)
              (finish-output *standard-output*)))))
    (end-of-file ()
      nil)
    (error (e)
      (format *error-output* "~&apeiron-mcp: fatal error: ~A~%" e)
      (finish-output *error-output*)
      (sb-ext:exit :code 1))))
