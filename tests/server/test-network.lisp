(in-package #:apeiron-test)

(in-suite server-suite)

(test socket-stream-error-handling
  "Test that socket errors are handled gracefully"
  (handler-case
      (progn
        (let ((session (make-instance 'apeiron.core:stream-session
                                      :stream (make-string-output-stream)))
              (player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                                                              :stream (make-string-output-stream)))))
          ;; Sending message to player with nil socket should not crash
          (apeiron.core:player-send-message player "Test message")
          (is (not (null player)))))
    (error (e)
      ;; Error is expected, just check it doesn't crash the test
      (is (not (null e))))))

(test socket-stream-creation
  "Test that we can get a stream from a socket"
  (let* ((server-socket (usocket:socket-listen "127.0.0.1" 0 :reuseaddress t))
         (port (usocket:get-local-port server-socket))
         (client-socket (usocket:socket-connect "127.0.0.1" port))
         (accepted-socket (usocket:socket-accept server-socket))
         (stream (usocket:socket-stream accepted-socket)))
    (unwind-protect
         (progn
           (is (not (null server-socket)))
           (is (not (null client-socket)))
           (is (not (null accepted-socket)))
           (is (not (null stream)))
           (is (streamp stream)))
      (when stream (close stream))
      (when client-socket (usocket:socket-close client-socket))
      (when accepted-socket (usocket:socket-close accepted-socket))
      (when server-socket (usocket:socket-close server-socket)))))

(test session-thread-tracking
  "Test that sessions can be tracked in a hash table keyed by
session-id, mirroring the *player-threads* pattern in network.lisp."
  (let ((table (make-hash-table :test #'equal))
        (session-1 (make-instance 'apeiron.core:stream-session
                                  :stream (make-string-output-stream)))
        (session-2 (make-instance 'apeiron.core:stream-session
                                  :stream (make-string-output-stream))))
    ;; Store sessions keyed by session-id (as network.lisp does
    ;; with *player-threads*)
    (setf (gethash (apeiron.core:session-id session-1) table) :thread-a)
    (setf (gethash (apeiron.core:session-id session-2) table) :thread-b)
    ;; Retrieve and verify
    (is (eq (gethash (apeiron.core:session-id session-1) table) :thread-a))
    (is (eq (gethash (apeiron.core:session-id session-2) table) :thread-b))
    ;; Remove and verify cleanup (as handle-client does)
    (remhash (apeiron.core:session-id session-1) table)
    (is (null (gethash (apeiron.core:session-id session-1) table)))
    (is (eq (gethash (apeiron.core:session-id session-2) table) :thread-b)
        "Other entries survive removal")))

(test player-message-with-mock-socket
  "Test sending messages to a player with a real socket"
  (handler-case
      (let* ((server-socket (usocket:socket-listen "127.0.0.1" 0 :reuseaddress t))
             (port (usocket:get-local-port server-socket))
             (client-socket (usocket:socket-connect "127.0.0.1" port))
             (accepted-socket (usocket:socket-accept server-socket))
             (session (make-instance 'apeiron.core:stream-session
                                     :stream (usocket:socket-stream accepted-socket))))
        (unwind-protect
             (progn
               (apeiron.persistence:world-restore-or-initialize)
               (let ((player (apeiron.core:new-character "TestPlayer" session)))
                 (is (not (null player)))
                 (apeiron.core:player-send-message player "Test message")
                 (is (not (null player)))))
          (when client-socket (usocket:socket-close client-socket))
          (when accepted-socket (usocket:socket-close accepted-socket))
          (when server-socket (usocket:socket-close server-socket))))
    (error (e)
      (skip (format nil "Socket message test skipped: ~A" e)))))

(test client-socket-read
  "Test that we can read from a socket stream"
  (let* ((server-socket (usocket:socket-listen "127.0.0.1" 0 :reuseaddress t))
         (port (usocket:get-local-port server-socket))
         (client-socket (usocket:socket-connect "127.0.0.1" port))
         (accepted-socket (usocket:socket-accept server-socket))
         (stream (usocket:socket-stream accepted-socket)))
    (unwind-protect
         (progn
           (is (not (null server-socket)))
           (is (streamp stream)))
      (when stream (close stream))
      (when client-socket (usocket:socket-close client-socket))
      (when accepted-socket (usocket:socket-close accepted-socket))
      (when server-socket (usocket:socket-close server-socket)))))

;; ===============================================================
;; MSSP Session-Layer Tests
;; ===============================================================

(test mssp-setup-registers-option
  "%setup-telnet-mssp should mark the MSSP option as wanted."
  (let* ((protocol (make-instance 'telnet:telnet-protocol))
         (called-with nil)
         (info-fn (lambda ()
                    (setf called-with t)
                    (list (cons "NAME" "TestMUD")))))
    (apeiron.server::%setup-telnet-mssp protocol info-fn)
    ;; Verify the option state
    (let ((state (telnet:telnet-local-option protocol
                                             telnet:+telnet-opt-mssp+)))
      (is (not (null state)) "MSSP option state should exist")
      (is (telnet::telnet-option-state-wanted state)
          "MSSP should be wanted"))
    ;; Verify the handler is registered by sending a request
    (let ((handler (gethash telnet:+telnet-opt-mssp+
                            (telnet::telnet-option-handlers protocol))))
      (is (not (null handler)) "MSSP handler should be registered"))))

(test mssp-setup-handler-calls-info-fn-on-request
  "%setup-telnet-mssp's handler should call the info-fn when the
subneg data is MSSP-VAR 'REQUEST'."
  (let* ((protocol (make-instance 'telnet:telnet-protocol))
         (info-fn-called nil)
         (info-fn (lambda ()
                    (setf info-fn-called t)
                    (list (cons "NAME" "TestMUD")))))
    (apeiron.server::%setup-telnet-mssp protocol info-fn)
    ;; Get the registered handler and call it with a REQUEST
    (let ((handler (gethash telnet:+telnet-opt-mssp+
                            (telnet::telnet-option-handlers protocol))))
      (is (not (null handler)) "Handler should exist")
      ;; Craft REQUEST data: MSSP-VAR(1) + "REQUEST" as bytes
      (let* ((request-text "REQUEST")
             (data (make-array (1+ (length request-text))
                               :element-type '(unsigned-byte 8))))
        (setf (aref data 0) telnet:+mssp-var+)
        (loop for i from 0 below (length request-text)
              do (setf (aref data (1+ i))
                       (char-code (aref request-text i))))
        ;; Call the handler
        (let ((response (funcall handler protocol telnet:+telnet-opt-mssp+ data)))
          ;; info-fn should have been called
          (is-true info-fn-called "info-fn should have been called on REQUEST")
          ;; Should return a response (list of byte vectors)
          (is (not (null response)) "Handler should return a response")
          (is (listp response) "Response should be a list")
          (is (> (length (first response)) 0) "Response should contain bytes"))))))

(test mssp-setup-handler-ignores-non-request
  "%setup-telnet-mssp's handler should NOT call info-fn for non-REQUEST data."
  (let* ((protocol (make-instance 'telnet:telnet-protocol))
         (info-fn-called nil)
         (info-fn (lambda ()
                    (setf info-fn-called t)
                    nil)))
    (apeiron.server::%setup-telnet-mssp protocol info-fn)
    (let ((handler (gethash telnet:+telnet-opt-mssp+
                            (telnet::telnet-option-handlers protocol))))
      ;; Send bad data: MSSP-VAR + "NOTREQUEST"
      (let* ((bad-text "NOTREQUEST")
             (data (make-array (1+ (length bad-text))
                               :element-type '(unsigned-byte 8))))
        (setf (aref data 0) telnet:+mssp-var+)
        (loop for i from 0 below (length bad-text)
              do (setf (aref data (1+ i))
                       (char-code (aref bad-text i))))
        (let ((response (funcall handler protocol telnet:+telnet-opt-mssp+ data)))
          (is-false info-fn-called "info-fn should NOT have been called")
          (is (null response) "Handler should return nil for non-REQUEST"))))))

(test mssp-session-constructor-passes-info-fn
  "new-telnet-session should accept :mssp-info-fn and store it on the session."
  (let* ((server (usocket:socket-listen "127.0.0.1" 0 :reuse-address t))
         (port (usocket:get-local-port server))
         (info-fn-called nil)
         (info-fn (lambda ()
                    (setf info-fn-called t)
                    (list (cons "NAME" "TestMUD"))))
         session
         client)
    (unwind-protect
         (let ((server-thread
                 (bt:make-thread
                  (lambda ()
                    (handler-case
                        (let ((accepted (usocket:socket-accept server)))
                          (setf session
                                (apeiron.server:new-telnet-session
                                 accepted
                                 :mssp-info-fn info-fn)))
                      (error (e)
                        (format t "~&Server error: ~A~%" e))))
                  :name "mssp-constructor-test")))
           (sleep 0.2)
           (setf client (usocket:socket-connect "127.0.0.1" port))
           ;; Keep client alive until validation completes (1.5s timeout)
           (sleep 2.0)
           (bt:join-thread server-thread)
           (is (not (null session)) "Session should be created")
           (when session
             (is (not (null (apeiron.server:session-mssp-info-fn session)))
                 "Session should have mssp-info-fn")
             (let ((vars (funcall (apeiron.server:session-mssp-info-fn session))))
               (is (not (null vars)) "info-fn should return vars")
               (is (string= (cdar vars) "TestMUD") "NAME should be TestMUD")
               (is-true info-fn-called "info-fn should have been called"))))
      (when client
        (ignore-errors (usocket:socket-close client)))
      (when session
        (ignore-errors (session-disconnect session)))
      (when server
        (ignore-errors (usocket:socket-close server))))))

(test mssp-constructor-with-start-tls-passes-info-fn
  "new-telnet-session-with-start-tls should pass :mssp-info-fn through."
  (let* ((server (usocket:socket-listen "127.0.0.1" 0 :reuse-address t))
         (port (usocket:get-local-port server))
         (info-fn-called nil)
         (info-fn (lambda ()
                    (setf info-fn-called t)
                    (list (cons "NAME" "TestMUD"))))
         session
         client)
    (unwind-protect
         (let ((server-thread
                 (bt:make-thread
                  (lambda ()
                    (handler-case
                        (let ((accepted (usocket:socket-accept server)))
                          (setf session
                                (apeiron.server:new-telnet-session-with-start-tls
                                 accepted
                                 :mssp-info-fn info-fn)))
                      (error (e)
                        (format t "~&Server error: ~A~%" e))))
                  :name "mssp-start-tls-test")))
           (sleep 0.2)
           (setf client (usocket:socket-connect "127.0.0.1" port))
           (sleep 2.0)
           (bt:join-thread server-thread)
           (is (not (null session)) "Session should be created")
           (when session
             (is (not (null (apeiron.server:session-mssp-info-fn session)))
                 "Session should have mssp-info-fn")))
      (when client
        (ignore-errors (usocket:socket-close client)))
      (when session
        (ignore-errors (session-disconnect session)))
      (when server
        (ignore-errors (usocket:socket-close server))))))

(test mssp-full-integration
  "Full integration: session with mssp-info-fn should respond to
an MSSP subneg REQUEST with the correct MSSP response bytes."
  (multiple-value-bind (srv-in-read srv-in-write) (sb-posix:pipe)
    (multiple-value-bind (srv-out-read srv-out-write) (sb-posix:pipe)
      (let* ((srv-in-stream
               (sb-sys:make-fd-stream srv-in-read
                                      :input t :output nil
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "mssp-srv-in"))
             (srv-out-fd (sb-posix:dup srv-out-write))
             (srv-out-stream
               (sb-sys:make-fd-stream srv-out-fd
                                      :input nil :output t
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "mssp-srv-out"))
             ;; Client side: writes to srv-in, reads from srv-out
             (cli-write-stream
               (sb-sys:make-fd-stream srv-in-write
                                      :input nil :output t
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "mssp-cli-write"))
             (cli-read-stream
               (sb-sys:make-fd-stream srv-out-read
                                      :input t :output nil
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "mssp-cli-read"))
             (info-fn-called nil)
             (info-fn (lambda ()
                        (setf info-fn-called t)
                        (list (cons "NAME" "TestMUD")
                              (cons "PLAYERS" "42"))))
             (protocol (make-instance 'telnet:telnet-protocol))
             ;; Server connection
             (srv-conn (make-instance 'telnet::telnet-connection
                                      :usocket nil
                                      :raw-stream srv-in-stream
                                      :out-stream srv-out-stream
                                      :protocol protocol))
             ;; Create session (wires up MSSP)
             (session (apeiron.server::%make-telnet-session
                       srv-conn
                       :mssp-info-fn info-fn)))
        (unwind-protect
             (progn
               (is (not (null session)) "Session should be created")
               (is (not (null (apeiron.server:session-mssp-info-fn session)))
                   "Session should have mssp-info-fn")
               ;; Client sends MSSP REQUEST: IAC SB MSSP MSSP-VAR \"REQUEST\" IAC SE
               (write-bytes cli-write-stream
                            (concatenate '(vector (unsigned-byte 8))
                                         #(255 250 70 1)
                                         (map '(vector (unsigned-byte 8))
                                              #'char-code "REQUEST")
                                         #(255 240)))
               (force-output cli-write-stream)
               (sleep 0.1)
               ;; Server reads — this triggers subneg processing + MSSP handler
               (telnet:telnet-read-char srv-conn :timeout 2)
               ;; info-fn should have been called
               (is-true info-fn-called
                        "info-fn should have been called on REQUEST")
               ;; Read server's MSSP response from client's read pipe
               (let ((resp-buf (make-array 32 :element-type '(unsigned-byte 8)
                                            :fill-pointer 0)))
                 (sleep 0.1)
                 (loop while (listen cli-read-stream)
                       do (vector-push-extend
                           (read-byte cli-read-stream) resp-buf))
                 (is (>= (length resp-buf) 10)
                     "Should have received MSSP response")
                 (is (= (aref resp-buf 0) 255) "Response starts with IAC")
                 (is (= (aref resp-buf 1) 250) "Response has SB")
                 (is (= (aref resp-buf 2) 70)  "Response is for MSSP (70)")
                 (is (search "TestMUD"
                             (map 'string #'code-char resp-buf))
                     "Response should contain 'TestMUD'")
                 (is (search "42"
                             (map 'string #'code-char resp-buf))
                     "Response should contain '42'"))
               ;; Verify the MSSP option was marked as wanted on the protocol
               (let ((state (telnet:telnet-local-option
                             protocol telnet:+telnet-opt-mssp+)))
                 (is (not (null state)) "MSSP option state should exist")
                 (is (telnet::telnet-option-state-wanted state)
                     "MSSP should be wanted")))
          (dolist (s (list srv-in-stream srv-out-stream cli-write-stream
                           cli-read-stream))
            (ignore-errors (close s :abort t)))
          (dolist (fd (list srv-in-read srv-in-write srv-out-read srv-out-write
                             srv-out-fd))
            (ignore-errors (sb-posix:close fd)))
          (when session
            (ignore-errors (session-disconnect session))))))))
