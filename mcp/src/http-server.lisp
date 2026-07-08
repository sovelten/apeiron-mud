;;;; mcp/src/http-server.lisp — HTTP transport for the MCP server
;;;;
;;;; Implements the MCP Streamable HTTP Transport (2025-11-25) using
;;;; Hunchentoot.  Listens on 127.0.0.1:3001 by default and dispatches
;;;; POST /mcp to the JSON-RPC 2.0 processor.
;;;;
;;;; Patterned after cl-mcp/src/http.lisp.
;;;;
;;;; Reference:
;;;;   https://spec.modelcontextprotocol.io/specification/2025-11-25/basic/transports/#streamable-http

(in-package #:apeiron-mcp/src/package)

;; ─── Server state ───────────────────────────────────────────────

(defvar *http-acceptor* nil
  "The Hunchentoot acceptor instance, or NIL when not running.")

(defvar *http-port* 3001
  "Port the HTTP server listens on.  Defaults to 3001 (cl-mcp uses 3000).")

;; ─── Session management ─────────────────────────────────────────

(defvar *http-sessions* (make-hash-table :test 'equal)
  "Hash-table mapping session-id string → state hash-table.")

(defvar *http-sessions-lock* (bordeaux-threads:make-lock "http-sessions-lock")
  "Lock serialising access to *HTTP-SESSIONS*.")

(defun %generate-session-id ()
  "Generate a random 32-byte hex session ID."
  (let ((id (make-array 64 :element-type 'character :fill-pointer 0)))
    (dotimes (i 64)
      (let ((nibble (random 16)))
        (vector-push-extend (char "0123456789abcdef" nibble) id)))
    id))

(defun %get-session-state (session-id)
  "Return the state hash-table for SESSION-ID, or NIL if not found."
  (bordeaux-threads:with-lock-held (*http-sessions-lock*)
    (gethash session-id *http-sessions*)))

(defun %create-session ()
  "Create a new HTTP session, returning its session-id."
  (let* ((id (%generate-session-id))
         (state (make-hash-table :test 'equal)))
    (bordeaux-threads:with-lock-held (*http-sessions-lock*)
      (setf (gethash id *http-sessions*) state))
    id))

(defun %delete-session (session-id)
  "Remove SESSION-ID from the session table."
  (bordeaux-threads:with-lock-held (*http-sessions-lock*)
    (remhash session-id *http-sessions*)))

;; ─── HTTP helpers ───────────────────────────────────────────────

(defun %request-header (name)
  "Get HTTP request header value."
  (hunchentoot:header-in name hunchentoot:*request*))

(defun (setf %response-header) (value name)
  "Set HTTP response header."
  (setf (hunchentoot:header-out name) value))

(defun %loopback-origin-p (origin)
  "Return T only if ORIGIN is a loopback address.
Uses prefix matching with boundary checks to prevent substring attacks."
  (flet ((check-prefix (prefix)
           (let ((len (length prefix)))
             (and (>= (length origin) len)
                  (string-equal origin prefix :end1 len)
                  (or (= (length origin) len)
                      (char= (char origin len) #\:)
                      (char= (char origin len) #\/))))))
    (or (check-prefix "http://localhost")
        (check-prefix "https://localhost")
        (check-prefix "http://127.0.0.1")
        (check-prefix "https://127.0.0.1")
        (check-prefix "http://[::1]")
        (check-prefix "https://[::1]"))))

(defun %set-cors-headers ()
  "Set CORS response headers for loopback origins."
  (let ((origin (%request-header :origin)))
    (when (and origin (%loopback-origin-p origin))
      (setf (%response-header :access-control-allow-origin) origin)))
  (setf (%response-header :access-control-expose-headers) "Mcp-Session-Id"))

(defun %sse-write (stream string)
  "Write STRING as UTF-8 bytes to the SSE binary STREAM.

Hunchentoot's SEND-HEADERS returns a binary (CHUNKED-IO-STREAM) that
only handles byte writes (WRITE-SEQUENCE, WRITE-BYTE).  Character I/O
calls via FORMAT or WRITE-STRING fail with 'no applicable method for
STREAM-WRITE-STRING'.  This helper encodes STRING to UTF-8 octets first
so the SSE handler can safely write event data."
  (let ((bytes (flexi-streams:string-to-octets string
                                               :external-format :utf-8)))
    (write-sequence bytes stream)
    (force-output stream)))

(defun %json-response (content &key (status 200))
  "Send a JSON response with the given HTTP status."
  (setf (hunchentoot:return-code*) status)
  (setf (hunchentoot:content-type*) "application/json")
  content)

(defun %json-error (code message &key (status 400))
  "Build and return a JSON-RPC error response."
  (%json-response (%encode-json (%error nil code message)) :status status))

;; ─── MCP dispatcher ─────────────────────────────────────────────

(defun %session-restore-connection (state)
  "Bind *MUD-CONNECTION* to the connection stored in STATE (if any).
Returns the previous value so the caller can restore it."
  (let ((old *mud-connection*)
        (session-conn (gethash :mud-conn state)))
    (when session-conn
      (setf *mud-connection* session-conn))
    old))

(defun %session-save-connection (state)
  "Save the current *MUD-CONNECTION* into STATE."
  (setf (gethash :mud-conn state) *mud-connection*))

(defun mcp-handler ()
  "Easy-handler function for /mcp.

Routes based on HTTP method:
- POST — JSON-RPC 2.0 requests (initialize, tools/list, tools/call, etc.)
- GET  — SSE stream for MUD activity notifications (requires active session + MUD connection)
- DELETE — tear down an HTTP session
- OPTIONS — CORS preflight"
  (%set-cors-headers)

  (case (hunchentoot:request-method*)
    (:post
     (let ((body (hunchentoot:raw-post-data :force-text t))
           (session-id (%request-header :mcp-session-id)))

       (unless body
         (return-from mcp-handler
           (%json-error -32700 "Parse error: empty body")))

       ;; Parse the JSON body
       (let ((parsed (handler-case
                         (%parse-json body)
                       (error (e)
                         (return-from mcp-handler
                           (%json-error -32700 (format nil "Parse error: ~A" e)))))))
         (unless (hash-table-p parsed)
           (return-from mcp-handler
             (%json-error -32600 "Invalid Request")))

         (let ((method (gethash "method" parsed)))
           (cond
             ;; Initialize → create a new session
             ((and method (string= method "initialize"))
              (let* ((sid (%create-session))
                     (state (make-hash-table :test 'equal)))
                (bordeaux-threads:with-lock-held (*http-sessions-lock*)
                  (setf (gethash sid *http-sessions*) state))
                (let ((response (%process-json-line body state)))
                  (setf (%response-header :mcp-session-id) sid)
                  (if response
                      (%json-response response)
                      (progn
                        (setf (hunchentoot:return-code*)
                              hunchentoot:+http-accepted+)
                        "")))))

             ;; Non-initialize without session-id → error
             ((null session-id)
              (%json-error -32600
                           "Missing Mcp-Session-Id header.  Call initialize first."))

             ;; Non-initialize with session-id → use session state
             (t
              (let ((state (%get-session-state session-id)))
                (unless state
                  (return-from mcp-handler
                    (%json-error -32600
                                 (format nil "Session ~A not found or expired"
                                         session-id)
                                 :status 404)))
                ;; Restore this session's MUD connection
                (let ((old-conn (%session-restore-connection state)))
                  (unwind-protect
                       (let ((response (%process-json-line body state)))
                         (%session-save-connection state)
                         (if response
                             (%json-response response)
                             (progn
                               (setf (hunchentoot:return-code*)
                                     hunchentoot:+http-accepted+)
                               "")))
                    (setf *mud-connection* old-conn))))))))))

    (:get
     ;; SSE — Server-Sent Events for MUD output notifications.
     (let ((session-id (%request-header :mcp-session-id)))
       (unless session-id
         (return-from mcp-handler
           (%json-error -32600 "Missing Mcp-Session-Id header for SSE")))
       (let ((state (%get-session-state session-id)))
         (unless state
           (return-from mcp-handler
             (%json-error -32600 (format nil "Session ~A not found" session-id)
                          :status 404)))
         ;; Restore this session's MUD connection, saving/restoring
         ;; *MUD-CONNECTION* so state doesn't leak between requests.
         (let ((sse-old-conn (%session-restore-connection state)))
           (unwind-protect
                (progn
                  (unless (mud-connected-p)
                    (return-from mcp-handler
                      (%json-error -32600
                                   "No active MUD connection. Use mud-connect first."
                                   :status 400)))

         ;; Set SSE headers
         (setf (hunchentoot:content-type*) "text/event-stream")
         (setf (hunchentoot:return-code*) 200)
         (setf (%response-header :cache-control) "no-cache")
         (setf (%response-header :connection) "keep-alive")

         ;; Use start-output to get a binary stream we can write to.
         ;; NOTE: SEND-HEADERS returns a CHUNKED-IO-STREAM (binary stream)
         ;; that does NOT support FORMAT / WRITE-STRING.  Use %SSE-WRITE.
         (let ((stream (hunchentoot:send-headers)))
           ;; Send initial SSE comment to flush headers through
           (%sse-write stream ":ok~%~%")
           ;; Stream MUD events via listen-for-activity callbacks
           (listen-for-activity
            :timeout (* 24 3600)
            :idle-timeout 1.0
            :callback
            (lambda (text status)
              (handler-case
                  (cond
                    ;; Connection lost → stop listening
                    ((eq status :disconnected)
                     :stop)
                    ;; MUD activity → encode as SSE notification
                    (t
                     (let ((notification
                             (%encode-json
                              (%make-ht
                               "jsonrpc" "2.0"
                               "method" "notifications/mud-output"
                               "params" (%make-ht "text" text)))))
                       (%sse-write stream (format nil "data: ~A~%~%" notification))
                       nil)))
                (stream-error (e)
                  (declare (ignore e))
                  :stop))))
           nil)
         ;; Restore *MUD-CONNECTION* after SSE ends
         (setf *mud-connection* sse-old-conn))
       ;; Close unwind-protect
       )
      ;; Close let(sse-old-conn)
      ))))

    (:delete
     (let ((session-id (%request-header :mcp-session-id)))
       (if session-id
           (progn
             (%delete-session session-id)
             (setf (hunchentoot:return-code*) 204)
             "")
           (%json-error -32600 "Missing Mcp-Session-Id header"))))

    (:options
     (setf (%response-header :access-control-allow-methods)
           "GET, POST, DELETE, OPTIONS")
     (setf (%response-header :access-control-allow-headers)
           "Content-Type, Accept, Authorization, Mcp-Session-Id")
     (setf (%response-header :access-control-max-age) "86400")
     (let ((origin (%request-header :origin)))
       (when (and origin (%loopback-origin-p origin))
         (setf (%response-header :access-control-allow-origin) origin)))
     (setf (hunchentoot:return-code*) 204)
     "")

    (otherwise
     (setf (hunchentoot:return-code*) 405)
     (setf (hunchentoot:content-type*) "text/plain")
     "Method not allowed")))

;; ─── Server lifecycle ───────────────────────────────────────────

(defun http-server-running-p ()
  "Return T when the HTTP server is running."
  (and *http-acceptor*
       (hunchentoot:started-p *http-acceptor*)))

(defun start-http-server (&key (host "127.0.0.1") (port *http-port*))
  "Start the MCP HTTP server on HOST:PORT.

Creates a Hunchentoot easy-acceptor with the /mcp handler and starts
it.  Returns the acceptor instance and port as two values."
  (when (http-server-running-p)
    (format *error-output* "~&apeiron-mcp: HTTP server already running on port ~D~%"
            *http-port*)
    (finish-output *error-output*)
    (return-from start-http-server (values *http-acceptor* *http-port*)))

  ;; Ensure the global state is ready
  (%ensure-state)

  (setf *http-port* port)

  ;; Use a unique acceptor name to avoid conflicts on restarts
  (let ((name (gensym "APEIRON-MCP-HTTP-")))
    (hunchentoot:define-easy-handler (mcp-endpoint :uri "/mcp"
                                                   :acceptor-names `(,name))
        ()
      (mcp-handler))

    (setf *http-acceptor*
          (make-instance 'hunchentoot:easy-acceptor
                         :address host
                         :port port
                         :name name
                         :access-log-destination nil
                         :message-log-destination nil))

    (hunchentoot:start *http-acceptor*))

  (format *error-output* "~&apeiron-mcp: HTTP server listening on http://~A:~D/mcp~%"
          host port)
  (finish-output *error-output*)

  (values *http-acceptor* port))

(defun stop-http-server ()
  "Stop the MCP HTTP server and clear all sessions."
  (when (http-server-running-p)
    (hunchentoot:stop *http-acceptor*)
    (setf *http-acceptor* nil)
    ;; Clear all sessions
    (bordeaux-threads:with-lock-held (*http-sessions-lock*)
      (clrhash *http-sessions*))
    (format *error-output* "~&apeiron-mcp: HTTP server stopped~%")
    (finish-output *error-output*))
  nil)

;; ─── Convenience: main entry point for HTTP mode ────────────────

(defun main-http ()
  "Entry point for HTTP mode.

Starts the HTTP server and blocks until a keyboard interrupt (Ctrl-C)
is received.

Usage (from command line):
  sbcl --load apeiron-mcp.asd --eval \"(apeiron-mcp/src/package:main-http)\""
  (start-http-server)
  (format *error-output* "~&apeiron-mcp: running, press Ctrl-C to stop~%")
  (finish-output *error-output*)
  (handler-case
      (loop (sleep 60))
    (sb-sys:interactive-interrupt ()
      (format *error-output* "~&apeiron-mcp: shutting down...~%")
      (finish-output *error-output*)
      (stop-http-server))))
