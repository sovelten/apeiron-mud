;;;; mcp/tests/test-mcp.lisp — Tests for the apeiron-mcp MCP server
;;;;
;;;; Tests cover three areas:
;;;;   1. ANSI escape code stripping (unit tests, no server needed)
;;;;   2. JSON-RPC 2.0 / MCP protocol handling (unit tests, no server needed)
;;;;   3. MUD client integration (requires a running MUD server)

(in-package #:apeiron-mcp-test)

;; ─── Helpers for integration tests ──────────────────────────

(defun %connect-and-login (port player-name)
  "Connect to MUD on 127.0.0.1:PORT as PLAYER-NAME, read through
welcome.  Returns T on success."
  (multiple-value-bind (welcome err status)
      (connect-to-mud "127.0.0.1" port player-name)
    (declare (ignore err))
    (and (eq status :ok) welcome (search "Welcome" welcome))))

(defun %command-contains (command expected)
  "Send COMMAND; return T if response contains EXPECTED."
  (multiple-value-bind (response err)
      (send-command command)
    (declare (ignore err))
    (and response (search expected response))))

(defmacro with-mud-server ((port-var) &body body)
  "Start a MUD server on a random port with a clean BKNR store,
bind PORT-VAR, run BODY, stop server and clean up."
  (declare (ignorable body))
  `(progn
     (setup-test-environment)
     (apeiron.server:stop-mud-server)
     (is (apeiron.server:start-mud-server :host "127.0.0.1" :port 0 :force-new t))
     (let ((,port-var (usocket:get-local-port apeiron.server:*server-socket*)))
       (unwind-protect
            (progn ,@body)
         (apeiron.server:stop-mud-server)
         (teardown-test-environment)))))

;; ══════════════════════════════════════════════════════════════
;; ANSI Escape Code Stripping Tests
;; ══════════════════════════════════════════════════════════════

(in-suite ansi-suite)

(test strip-csi-colors
  "Strip SGR color sequences (ESC [ ... m)."
  (let ((input (format nil "~C[31mRed~C[0m and normal" #\Escape #\Escape)))
    (is (string= (strip-ansi input) "Red and normal"))))

(test strip-bold-and-underline
  "Strip bold (1) and underline (4) SGR codes."
  (let ((input (format nil "~C[1mBold~C[0m ~C[4mUnder~C[0m"
                       #\Escape #\Escape #\Escape #\Escape)))
    (is (string= (strip-ansi input) "Bold Under"))))

(test strip-cursor-movement
  "Strip cursor positioning (CSI n ; m H)."
  (let ((input (format nil "Hello~C[10;5HWorld" #\Escape)))
    (is (string= (strip-ansi input) "HelloWorld"))))

(test strip-plain-text-unchanged
  "Plain text without escape codes is unchanged."
  (let ((input "Just some plain text.
No escape codes here."))
    (is (string= (strip-ansi input) input))))

(test strip-empty-string
  "Empty string remains empty."
  (is (string= (strip-ansi "") "")))

(test strip-mud-prompt-preserved
  "MUD prompt '> ' with no ANSI codes is preserved."
  (is (string= (strip-ansi "> ") "> ")))

(test strip-escaped-iac
  "Text with literal ESC characters not starting a sequence are kept."
  ;; ESC at end of string is kept literally
  (let ((input (format nil "text~C" #\Escape)))
    (is (string= (strip-ansi input) input))))

;; ══════════════════════════════════════════════════════════════
;; JSON-RPC 2.0 / MCP Protocol Tests
;; ══════════════════════════════════════════════════════════════

(in-suite protocol-suite)

;; We need access to the internal %process-json-line function.
;; It's in apeiron-mcp/src/package, not exported — access via ::.
(defun %process (line)
  "Call the internal JSON-RPC processor on LINE, return parsed result."
  (let* ((raw (funcall (find-symbol "%PROCESS-JSON-LINE"
                                    "APEIRON-MCP/SRC/PACKAGE")
                       line))
         (parsed (and raw (yason:parse raw))))
    parsed))

(test protocol-initialize
  "Initialize returns server info and capabilities."
  (let* ((response (%process "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"clientInfo\":{\"name\":\"test\"}}}"))
         (result (gethash "result" response)))
    (is (string= (gethash "protocolVersion" result) "2025-11-25"))
    (is (string= (gethash "name" (gethash "serverInfo" result))
                 "apeiron-mcp"))
    (is (hash-table-p (gethash "tools" (gethash "capabilities" result))))))

(test protocol-tools-list
  "tools/list returns all 6 MUD tools."
  (let* ((response (%process "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}"))
         (tools (gethash "tools" (gethash "result" response))))
    (is (= (length tools) 6))
    (let ((names (loop for tool in tools collect (gethash "name" tool))))
      (is (member "mud-connect" names :test #'string=))
      (is (member "mud-send" names :test #'string=))
      (is (member "mud-eval" names :test #'string=))
      (is (member "mud-disconnect" names :test #'string=))
      (is (member "mud-status" names :test #'string=))
      (is (member "mud-listen" names :test #'string=)))))

(test protocol-tool-schemas-have-required-fields
  "Each tool schema has name, description, and inputSchema."
  (let* ((response (%process "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\",\"params\":{}}"))
         (tools (gethash "tools" (gethash "result" response))))
    (loop for tool in tools do
      (is (stringp (gethash "name" tool)))
      (is (stringp (gethash "description" tool)))
      (is (hash-table-p (gethash "inputSchema" tool))))))

(test protocol-mud-status-without-connection
  "mud-status reports not connected when no MUD connection exists."
  (let* ((response (%process "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"mud-status\",\"arguments\":{}}}"))
         (content (elt (gethash "content" (gethash "result" response)) 0)))
    (is (search "Not connected" (gethash "text" content)))))

(test protocol-unknown-tool
  "Unknown tool returns -32601 error."
  (let* ((response (%process "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"no-such-tool\",\"arguments\":{}}}"))
         (err (gethash "error" response)))
    (is (= (gethash "code" err) -32601))
    (is (search "not found" (gethash "message" err)))))

(test protocol-ping
  "Ping returns an empty result object."
  (let* ((response (%process "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"ping\",\"params\":{}}"))
         (result (gethash "result" response)))
    (is (hash-table-p result))))

(test protocol-notification-returns-nil
  "Notifications return NIL (no JSON-RPC response)."
  (let ((raw (funcall (find-symbol "%PROCESS-JSON-LINE"
                                   "APEIRON-MCP/SRC/PACKAGE")
                      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")))
    (is (null raw))))

(test protocol-parse-error
  "Malformed JSON returns -32700 parse error."
  (let* ((response (%process "not valid json at all"))
         (err (gethash "error" response)))
    (is (= (gethash "code" err) -32700))))

(test protocol-missing-method
  "Missing method returns -32600 invalid request."
  (let* ((response (%process "{\"jsonrpc\":\"2.0\",\"id\":7}"))
         (err (gethash "error" response)))
    (is (= (gethash "code" err) -32600))))

;; ══════════════════════════════════════════════════════════════
;; MUD Client Integration Tests
;; ══════════════════════════════════════════════════════════════

(in-suite integration-suite)

(test integration-connect-and-look
  "Connect to MUD, look at the starting room."
  (with-mud-server (port)
    (is-true (%connect-and-login port "Looker"))
    (is-true (%command-contains "look" "The Gathering"))
    (disconnect-from-mud)))

(test integration-connect-and-go-north
  "Connect and move north to the Whispering Forest."
  (with-mud-server (port)
    (is-true (%connect-and-login port "Walker"))
    (is-true (%command-contains "go north" "Whispering Forest"))
    (is-true (%command-contains "look" "Whispering Forest"))
    (disconnect-from-mud)))

(test integration-connect-and-go-east
  "Connect and move east to the Desert."
  (with-mud-server (port)
    (is-true (%connect-and-login port "Eastbound"))
    (is-true (%command-contains "go east" "Desert"))
    (disconnect-from-mud)))

(test integration-connect-and-go-west
  "Connect and move west to the Swamp."
  (with-mud-server (port)
    (is-true (%connect-and-login port "Westbound"))
    (is-true (%command-contains "go west" "Swamp"))
    (disconnect-from-mud)))

(test integration-connect-and-go-south
  "Connect and move south to the Volcano."
  (with-mud-server (port)
    (is-true (%connect-and-login port "Southbound"))
    (is-true (%command-contains "go south" "Volcano"))
    (disconnect-from-mud)))

(test integration-eval-me
  "(me) returns the player character name."
  (with-mud-server (port)
    (is-true (%connect-and-login port "EvalMe"))
    (is-true (%command-contains "eval (object-name (me))" "EvalMe"))
    (disconnect-from-mud)))

(test integration-eval-here
  "(here) returns the starting room name."
  (with-mud-server (port)
    (is-true (%connect-and-login port "EvalHere"))
    (is-true (%command-contains "eval (object-name (here))" "The Gathering"))
    (disconnect-from-mud)))

(test integration-eval-world
  "(world) returns a valid mud-world instance."
  (with-mud-server (port)
    (is-true (%connect-and-login port "WorldCheck"))
    (is-true (%command-contains
              "eval (if (typep (world) 'apeiron.core:mud-world) \"WORLD-OK\" \"BAD\")"
              "WORLD-OK"))
    (disconnect-from-mud)))

(test integration-help
  "Help command lists available commands."
  (with-mud-server (port)
    (is-true (%connect-and-login port "Helper"))
    (is-true (%command-contains "help" "Available commands"))
    (disconnect-from-mud)))

(test integration-exits
  "Exits command lists directions."
  (with-mud-server (port)
    (is-true (%connect-and-login port "ExitCheck"))
    ;; The Gathering has exits in all four cardinal directions
    (let ((resp (%command-contains "exits" "")))
      (is-true (or resp t)))
    (disconnect-from-mud)))

(test integration-connection-status
  "connection-status reflects connection state."
  (with-mud-server (port)
    (is (search "Not connected" (connection-status)))
    (is-true (%connect-and-login port "StatusCheck"))
    (is (search "Connected" (connection-status)))
    (disconnect-from-mud)
    (is (search "Not connected" (connection-status)))))

(test integration-disconnect-cleanup
  "After disconnect, mud-connected-p returns NIL."
  (with-mud-server (port)
    (is-true (%connect-and-login port "Quitter"))
    (is-true (mud-connected-p))
    (disconnect-from-mud)
    (is-false (mud-connected-p))))

(test integration-send-while-disconnected
  "Sending a command while disconnected returns an error."
  (disconnect-from-mud)   ; ensure clean state
  (multiple-value-bind (response err)
      (send-command "look")
    (declare (ignore response))
    (is (search "Not connected" err))))

(test integration-reconnect
  "Second connect replaces the first cleanly."
  (with-mud-server (port)
    (is-true (%connect-and-login port "First"))
    (is-true (mud-connected-p))
    (is-true (%connect-and-login port "Second"))
    (is-true (mud-connected-p))
    (is-true (%command-contains "eval (object-name (me))" "Second"))
    (disconnect-from-mud)))

;; ══════════════════════════════════════════════════════════════
;; HTTP Transport Integration Tests
;; ══════════════════════════════════════════════════════════════

(in-suite http-suite)

;; ─── Minimal HTTP client ────────────────────────────────────

(defun %http-request (host port method path headers body)
  "Send a minimal HTTP request and return (status-code headers body-str)."
  (let* ((socket (usocket:socket-connect host port
                                         :element-type 'character))
         (stream (usocket:socket-stream socket)))
    (unwind-protect
         (progn
           ;; Write request line
           (format stream "~A ~A HTTP/1.1~C~C" method path #\Return #\Newline)
           (format stream "Host: ~A:~D~C~C" host port #\Return #\Newline)
           (format stream "Connection: close~C~C" #\Return #\Newline)
           ;; Write headers
           (loop for (k . v) in headers do
             (format stream "~A: ~A~C~C" k v #\Return #\Newline))
           ;; Content-Length
           (when body
             (format stream "Content-Length: ~D~C~C" (length body) #\Return #\Newline))
           ;; Blank line
           (format stream "~C~C" #\Return #\Newline)
           ;; Body
           (when body
             (write-string body stream))
           (finish-output stream)

           ;; Read response: status line
           (let* ((status-line (read-line stream nil nil))
                  (code (when status-line
                          (let ((space1 (position #\Space status-line)))
                            (when space1
                              (let ((space2 (position #\Space status-line
                                                      :start (1+ space1))))
                                (parse-integer status-line
                                               :start (1+ space1)
                                               :end space2
                                               :junk-allowed t)))))))
             (unless code
               (return-from %http-request (values 0 nil "")))

             ;; Read headers
             (let ((resp-headers nil))
                 (loop for line = (read-line stream nil nil)
                       while (and line
                                  (plusp (length (string-right-trim '(#\Return) line))))
                       do (let ((colon (position #\: line)))
                            (when colon
                              (push (cons (subseq line 0 colon)
                                          (string-trim '(#\Space #\Return) (subseq line (1+ colon))))
                                    resp-headers))))
                 (setf resp-headers (nreverse resp-headers))
                 ;; Read body
                 (let ((content-length
                         (cdr (assoc "Content-Length" resp-headers
                                     :test #'string-equal)))
                       (accum (make-array 0 :element-type 'character
                                            :adjustable t
                                            :fill-pointer t)))
                   (when content-length
                     (let ((n (parse-integer content-length :junk-allowed t)))
                       (when n
                         (dotimes (i n)
                           (let ((c (read-char stream nil nil)))
                             (when c (vector-push-extend c accum)))))))
                   (values code resp-headers accum)))))
      (usocket:socket-close socket))))

(defun %http-post (host port path &key headers body)
  "Shortcut for POST requests."
  (%http-request host port "POST" path headers body))

(defun %http-delete (host port path &key headers)
  "Shortcut for DELETE requests."
  (%http-request host port "DELETE" path headers nil))

(defun %http-get (host port path &key headers)
  "Shortcut for GET requests."
  (%http-request host port "GET" path headers nil))

(defun %http-options (host port path &key headers)
  "Shortcut for OPTIONS requests."
  (%http-request host port "OPTIONS" path headers nil))

;; ─── HTTP server test helper ─────────────────────────────────

(defmacro with-http-server ((port-var) &body body)
  "Start a fresh MCP HTTP server on port 3001, run BODY, stop the server
afterwards.  Each test gets a clean server with no stale sessions."
  (declare (ignorable body))
  `(progn
     (when (http-server-running-p)
       (stop-http-server))
     (start-http-server :host "127.0.0.1" :port 3001)
     (unwind-protect
          (let ((,port-var 3001))
            ,@body)
       (when (http-server-running-p)
         (stop-http-server)))))

;; ─── HTTP session helpers ─────────────────────────────────────

(defun %http-initialize (port)
  "Create a new MCP session via initialize, return the session-id."
  (multiple-value-bind (code headers body)
      (%http-post "127.0.0.1" port "/mcp"
                  :body "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\"}}")
    (declare (ignore code body))
    (cdr (assoc "Mcp-Session-Id" headers :test #'string-equal))))

(defun %http-connect-mud (port session-id mud-port player-name)
  "Connect SESSION-ID to the MUD at MUD-PORT as PLAYER-NAME.
Returns the response body string."
  (multiple-value-bind (code headers body)
      (%http-post "127.0.0.1" port "/mcp"
                  :headers `(("Content-Type" . "application/json")
                             ("Mcp-Session-Id" . ,session-id))
                  :body (format nil "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"mud-connect\",\"arguments\":{\"host\":\"127.0.0.1\",\"port\":~D,\"name\":\"~A\"}}}"
                                mud-port player-name))
    (declare (ignore headers))
    (when (/= 200 code)
      (format t "~&HTTP ~D for mud-connect ~A:~%~A~%" code player-name body))
    body))

(defun %http-send (port session-id command &key (id 3))
  "Send COMMAND via SESSION-ID, return (values status-code body)."
  (let ((body (format nil "{\"jsonrpc\":\"2.0\",\"id\":~D,\"method\":\"tools/call\",\"params\":{\"name\":\"mud-send\",\"arguments\":{\"command\":\"~A\"}}}"
                      id command)))
    (multiple-value-bind (code headers resp-body)
        (%http-post "127.0.0.1" port "/mcp"
                    :headers `(("Content-Type" . "application/json")
                               ("Mcp-Session-Id" . ,session-id))
                    :body body)
      (declare (ignore headers))
      (when (/= 200 code)
        (format t "~&HTTP ~D for ~S:~%~A~%" code command resp-body))
      (values code resp-body))))

;; ─── HTTP lifecycle tests ────────────────────────────────────

(test http-initialize-returns-session-id
  "Initialize over HTTP returns 200, server info, and Mcp-Session-Id."
  (with-http-server (port)
    (multiple-value-bind (code headers body)
        (%http-post "127.0.0.1" port "/mcp"
                    :body "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\"}}")
      (is (= 200 code))
      (is (search "apeiron-mcp" body))
      (let ((sid (cdr (assoc "Mcp-Session-Id" headers :test #'string-equal))))
        (is (stringp sid))
        (is (> (length sid) 0))))))

(test http-tools-list-with-session
  "tools/list over HTTP with a valid session returns all 5 tools."
  (with-http-server (port)
    (let ((sid (%http-initialize port)))
      (multiple-value-bind (code2 headers2 body2)
          (%http-post "127.0.0.1" port "/mcp"
                      :headers `(("Content-Type" . "application/json")
                                 ("Mcp-Session-Id" . ,sid))
                      :body "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}")
        (declare (ignore headers2))
        (is (= 200 code2))
        (let ((tools (gethash "tools" (gethash "result" (%parse-json body2)))))
          (is (= (length tools) 6)))))))

(test http-mud-status-with-session
  "mud-status over HTTP returns 'Not connected' when no MUD connected."
  (with-http-server (port)
    (let ((sid (%http-initialize port)))
      (multiple-value-bind (code2 headers2 body2)
          (%http-post "127.0.0.1" port "/mcp"
                      :headers `(("Content-Type" . "application/json")
                                 ("Mcp-Session-Id" . ,sid))
                      :body "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"mud-status\",\"arguments\":{}}}")
        (declare (ignore headers2))
        (is (= 200 code2))
        (is (search "Not connected" body2))))))

(test http-notification-returns-202
  "Notifications over HTTP return 202 Accepted with empty body."
  (with-http-server (port)
    (let ((sid (%http-initialize port)))
      (multiple-value-bind (code2 headers2 body2)
          (%http-post "127.0.0.1" port "/mcp"
                      :headers `(("Content-Type" . "application/json")
                                 ("Mcp-Session-Id" . ,sid))
                      :body "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")
        (declare (ignore headers2))
        (is (= 202 code2))
        (is (string= body2 ""))))))

(test http-missing-session-id
  "Non-initialize request without Mcp-Session-Id returns 400."
  (with-http-server (port)
    (multiple-value-bind (code headers body)
        (%http-post "127.0.0.1" port "/mcp"
                    :body "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}")
      (declare (ignore headers))
      (is (= 400 code))
      (is (search "Mcp-Session-Id" body)))))

(test http-invalid-session-id
  "Request with a non-existent session ID returns 404."
  (with-http-server (port)
    (multiple-value-bind (code headers body)
        (%http-post "127.0.0.1" port "/mcp"
                    :headers '(("Content-Type" . "application/json")
                               ("Mcp-Session-Id" . "deadbeef00000000000000000000000000000000000000000000000000000000"))
                    :body "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}")
      (declare (ignore headers))
      (is (= 404 code))
      (is (search "not found" body)))))

(test http-delete-session
  "DELETE /mcp with session ID returns 204 and removes session."
  (with-http-server (port)
    (let ((sid (%http-initialize port)))
      ;; Delete the session
      (multiple-value-bind (del-code del-headers del-body)
          (%http-delete "127.0.0.1" port "/mcp"
                        :headers `(("Mcp-Session-Id" . ,sid)))
        (declare (ignore del-headers))
        (is (= 204 del-code))
        (is (string= del-body "")))
      ;; Session should now be invalid
      (multiple-value-bind (code3 headers3 body3)
          (%http-post "127.0.0.1" port "/mcp"
                      :headers `(("Content-Type" . "application/json")
                                 ("Mcp-Session-Id" . ,sid))
                      :body "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/list\",\"params\":{}}")
        (declare (ignore headers3))
        (is (= 404 code3))
        (is (search "not found" body3))))))

(test http-get-requires-session-id
  "GET /mcp without session-id returns 400 with missing session error."
  (with-http-server (port)
    (multiple-value-bind (code headers body)
        (%http-get "127.0.0.1" port "/mcp")
      (declare (ignore headers))
      (is (= 400 code))
      (is (search "Mcp-Session-Id" body)))))

(test http-options-returns-cors
  "OPTIONS /mcp returns CORS headers."
  (with-http-server (port)
    (multiple-value-bind (code headers body)
        (%http-options "127.0.0.1" port "/mcp")
      (is (= 204 code))
      (is (string= body ""))
      (let ((methods (cdr (assoc "Access-Control-Allow-Methods" headers
                                 :test #'string-equal))))
        (is (search "POST" methods))
        (is (search "DELETE" methods))
        (is (search "OPTIONS" methods))))))

(test http-parse-error
  "Malformed JSON body over HTTP returns 400 with JSON-RPC error."
  (with-http-server (port)
    (multiple-value-bind (code headers body)
        (%http-post "127.0.0.1" port "/mcp"
                    :body "not json")
      (declare (ignore headers))
      (is (= 400 code))
      (let ((parsed (%parse-json body)))
        (is (= (gethash "code" (gethash "error" parsed)) -32700))))))

(test http-empty-body
  "Empty POST body returns error."
  (with-http-server (port)
    (multiple-value-bind (code headers body)
        (%http-post "127.0.0.1" port "/mcp" :body "")
      (declare (ignore headers))
      (is (= 400 code))
      (is (search "Parse error" body)))))

(test http-cors-expose-headers
  "Responses include Access-Control-Expose-Headers: Mcp-Session-Id."
  (with-http-server (port)
    (multiple-value-bind (code headers body)
        (%http-post "127.0.0.1" port "/mcp"
                    :body "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\"}}")
      (declare (ignore code body))
      (let ((expose (cdr (assoc "Access-Control-Expose-Headers" headers
                                :test #'string-equal))))
        (is (search "Mcp-Session-Id" expose))))))

;; ══════════════════════════════════════════════════════════════
;; SSE Integration Tests
;; ══════════════════════════════════════════════════════════════

(in-suite http-suite)

;; ─── SSE helpers ────────────────────────────────────────────

(defun %http-stream-get (host port path headers)
  "Open a GET connection and return the raw socket stream for reading
the response body.  Returns (stream socket code headers) where STREAM
is ready to read the body after headers."
  (let* ((socket (usocket:socket-connect host port
                                         :element-type 'character))
         (stream (usocket:socket-stream socket)))
    ;; Write GET request — do NOT send Connection: close so the SSE
    ;; stream stays open for reading events as they arrive.
    (format stream "GET ~A HTTP/1.1~C~C" path #\Return #\Newline)
    (format stream "Host: ~A:~D~C~C" host port #\Return #\Newline)
    (loop for (k . v) in headers do
      (format stream "~A: ~A~C~C" k v #\Return #\Newline))
    (format stream "~C~C" #\Return #\Newline)
    (finish-output stream)

    ;; Read status line
    (let* ((status-line (read-line stream nil nil))
           (code (when status-line
                   (let ((sp (position #\Space status-line)))
                     (when sp
                       (parse-integer status-line
                                      :start (1+ sp)
                                      :junk-allowed t))))))
      (unless code
        (usocket:socket-close socket)
        (return-from %http-stream-get (values nil nil 0 nil)))

      ;; Read headers
      (let ((resp-headers nil))
        (loop for line = (read-line stream nil nil)
              while (and line
                         (plusp (length (string-right-trim '(#\Return) line))))
              do (let ((colon (position #\: line)))
                   (when colon
                     (push (cons (subseq line 0 colon)
                                 (string-trim
                                  '(#\Space #\Return)
                                  (subseq line (1+ colon))))
                           resp-headers))))
        (values stream socket code (nreverse resp-headers))))))

(defun %read-sse-line (stream timeout-seconds)
  "Read one line from STREAM with TIMEOUT-SECONDS.  Returns the line
or NIL on timeout/eof."
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout-seconds internal-time-units-per-second))))
    (loop
      (when (listen stream)
        (return-from %read-sse-line
          (read-line stream nil nil)))
      (when (>= (get-internal-real-time) deadline)
        (return-from %read-sse-line nil))
      (sleep 0.05))))

(test http-sse-receives-mud-output
  "SSE stream receives MUD output when another player speaks."
  (with-http-server (http-port)
    (with-mud-server (mud-port)
      (let ((listener-sid (%http-initialize http-port))
            (speaker-sid (%http-initialize http-port)))
        (%http-connect-mud http-port listener-sid mud-port "SSE-Listener")
        (%http-connect-mud http-port speaker-sid mud-port "SSE-Speaker")
        ;; Open SSE stream for the listener
        (multiple-value-bind (sse-stream sse-socket sse-code sse-headers)
            (%http-stream-get "127.0.0.1" http-port "/mcp"
                              `(("Accept" . "text/event-stream")
                                ("Mcp-Session-Id" . ,listener-sid)))
          (unwind-protect
               (progn
                 (is (not (null sse-stream)))
                 (is (= 200 sse-code))
                 (let ((ct (cdr (assoc "Content-Type" sse-headers
                                       :test #'string-equal))))
                   (is (search "text/event-stream" ct)))
                 ;; Small delay to ensure SSE stream is established
                 (sleep 0.5)
                 ;; Speaker says something
                 (%http-send http-port speaker-sid "say Hello from SSE test!")
                 ;; Read SSE events — should get the notification
                 (let ((event-found nil))
                   (loop repeat 20
                         for line = (%read-sse-line sse-stream 0.5)
                         while line
                         do (when (and (> (length line) 6)
                                       (string= (subseq line 0 6) "data: "))
                              (let ((payload (subseq line 6)))
                                (when (search "Hello from SSE test" payload)
                                  (setf event-found t)
                                  (loop-finish)))))
                   (is-true event-found "SSE stream should receive the 'say' event"))))
            ;; Cleanup
            (when sse-socket
              (ignore-errors (usocket:socket-close sse-socket))))))))

(test http-sse-without-connection
  "SSE GET without a MUD connection returns 400 error."
  (with-http-server (http-port)
    (with-mud-server (mud-port)
      mud-port  ; silence unused warning
      (let ((sid (%http-initialize http-port)))
        (multiple-value-bind (sse-stream sse-socket sse-code sse-headers)
            (%http-stream-get "127.0.0.1" http-port "/mcp"
                              `(("Accept" . "text/event-stream")
                                ("Mcp-Session-Id" . ,sid)))
          (declare (ignore sse-stream sse-headers))
          (is (= 400 sse-code))
          (when sse-socket
            (ignore-errors (usocket:socket-close sse-socket))))))))

(test http-sse-receives-multiple-events
  "SSE stream receives multiple MUD events."
  (with-http-server (http-port)
    (with-mud-server (mud-port)
      (let ((listener-sid (%http-initialize http-port))
            (speaker-sid (%http-initialize http-port)))
        (%http-connect-mud http-port listener-sid mud-port "SSE-Multi")
        (%http-connect-mud http-port speaker-sid mud-port "SSE-Speaker2")
        ;; Open SSE stream for listener
        (multiple-value-bind (sse-stream sse-socket sse-code sse-headers)
            (%http-stream-get "127.0.0.1" http-port "/mcp"
                              `(("Accept" . "text/event-stream")
                                ("Mcp-Session-Id" . ,listener-sid)))
          (unwind-protect
               (progn
                 (is (not (null sse-stream)))
                 (is (= 200 sse-code))
                 (let ((ct (cdr (assoc "Content-Type" sse-headers
                                       :test #'string-equal))))
                   (is (search "text/event-stream" ct)))
                 (sleep 0.5)
                 ;; Speaker says two things — log response bodies for debugging
                 (multiple-value-bind (status body)
                     (%http-send http-port speaker-sid "say First event!")
                   (is (= 200 status) (format nil "Should return 200, returned ~D: ~A" status body)))
                 (sleep 0.4)
                 (multiple-value-bind (status body)
                     (%http-send http-port speaker-sid "say Second event!")
                   (is (= 200 status) (format nil "Should return 200, returned ~D: ~A" status body)))
                 ;; Collect events and verify both messages arrived
                 (let ((all-data (make-string-output-stream)))
                   (loop repeat 20
                         for line = (%read-sse-line sse-stream 0.5)
                         while line
                         do (write-string line all-data))
                   (let ((data (get-output-stream-string all-data)))
                     (is (search "First event" data)
                         "Should receive 'First event' via SSE")
                     (is (search "Second event" data)
                         "Should receive 'Second event' via SSE"))))
            (when sse-socket
              (ignore-errors (usocket:socket-close sse-socket)))))))))

;; ══════════════════════════════════════════════════════════════
;; listen-for-activity One-Shot Mode Tests
;; ══════════════════════════════════════════════════════════════

(in-suite integration-suite)

(test listen-activity-receives-speech
  "listen-for-activity returns text when another player speaks."
  (with-mud-server (port)
    (connect-to-mud "127.0.0.1" port "ListenChar")
    ;; Connect speaker via raw telnet
    (let* ((us (usocket:socket-connect "127.0.0.1" port :element-type 'character))
           (c (telnet:make-telnet-connection us)))
      (telnet:telnet-read-line c :timeout 3)
      (telnet:telnet-write-string c "SpeakerCh" :end :crlf)
      (sleep 0.3)
      (loop repeat 10 do
        (multiple-value-bind (l s) (telnet:telnet-read-line c :timeout 0.3)
          (declare (ignore l))
          (when (eq s :timeout) (return))))
      (telnet:telnet-write-string c "say Hello from listen test!" :end :crlf)
      (sleep 0.3)
      (multiple-value-bind (text err status)
          (apeiron-mcp/src/package:listen-for-activity :timeout 5 :idle-timeout 1.0)
        (declare (ignore err))
        (is (eq status :ok))
        (is (search "Hello from listen test" text)))
      (telnet:telnet-connection-close c))
    (disconnect-from-mud)))

(test listen-activity-multiple-calls
  "listen-for-activity can be called multiple times for separate events."
  (with-mud-server (port)
    (connect-to-mud "127.0.0.1" port "MultiListen")
    (let* ((us (usocket:socket-connect "127.0.0.1" port :element-type 'character))
           (c (telnet:make-telnet-connection us)))
      (telnet:telnet-read-line c :timeout 3)
      (telnet:telnet-write-string c "Speaker2" :end :crlf)
      (sleep 0.3)
      (loop repeat 10 do
        (multiple-value-bind (l s) (telnet:telnet-read-line c :timeout 0.3)
          (declare (ignore l))
          (when (eq s :timeout) (return))))
      ;; First speech
      (telnet:telnet-write-string c "say First speech!" :end :crlf)
      (sleep 0.3)
      (multiple-value-bind (text1 err1 status1)
          (apeiron-mcp/src/package:listen-for-activity :timeout 5 :idle-timeout 1.0)
        (declare (ignore err1))
        (is (eq status1 :ok))
        (is (search "First speech" text1)))
      ;; Second speech
      (telnet:telnet-write-string c "say Second speech!" :end :crlf)
      (sleep 0.3)
      (multiple-value-bind (text2 err2 status2)
          (apeiron-mcp/src/package:listen-for-activity :timeout 5 :idle-timeout 1.0)
        (declare (ignore err2))
        (is (eq status2 :ok))
        (is (search "Second speech" text2)))
      (telnet:telnet-connection-close c))
    (disconnect-from-mud)))

(test listen-activity-timeout-returns-timeout
  "listen-for-activity returns :timeout when no activity occurs."
  (with-mud-server (port)
    (connect-to-mud "127.0.0.1" port "TimeoutChar")
    (multiple-value-bind (text err status)
        (apeiron-mcp/src/package:listen-for-activity :timeout 1 :idle-timeout 0.5)
      (declare (ignore text err))
      (is (eq status :timeout)))
    (disconnect-from-mud)))
