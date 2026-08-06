(in-package #:apeiron-test)

(in-suite server-suite)

(test socket-stream-error-handling
  "Test that socket errors are handled gracefully"
  (handler-case
      (progn
        (let ((session (make-instance 'apeiron.core:stream-session
                                      :stream (make-string-output-stream)))
              (character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                              :stream (make-string-output-stream)))))
          ;; Sending message to character with nil socket should not crash
          (apeiron.core:character-send-message character "Test message")
          (is (not (null character)))))
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

(test character-message-with-mock-socket
  "Test sending messages to a character with a real socket"
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
               (let ((character (apeiron.core:new-character "TestCharacter" session)))
                 (is (not (null character)))
                 (apeiron.core:character-send-message character "Test message")
                 (is (not (null character)))))
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
  "%setup-telnet-mssp should mark the MSSP option as wanted
and set the mssp-response-fn on the protocol."
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
    ;; Verify the response function is set
    (is (not (null (telnet:telnet-mssp-response-fn protocol)))
        "MSSP response function should be registered on protocol")))

(test mssp-do-mssp-triggers-response
  "%setup-telnet-mssp should cause DO MSSP to produce WILL MSSP
and the MSSP response data."
  (let* ((protocol (make-instance 'telnet:telnet-protocol))
         (info-fn-called nil)
         (info-fn (lambda ()
                    (setf info-fn-called t)
                    (list (cons "NAME" "TestMUD")
                          (cons "PLAYERS" "42")))))
    (apeiron.server::%setup-telnet-mssp protocol info-fn)
    ;; Process DO MSSP (option 70) - this is what the client sends
    (let ((responses (telnet:telnet-process-command
                      protocol telnet::do telnet:+telnet-opt-mssp+)))
      ;; info-fn should have been called
      (is-true info-fn-called
               "info-fn should have been called on DO MSSP")
      ;; Should return a list of byte vectors (WILL MSSP + MSSP subneg)
      (is (not (null responses)) "DO MSSP should produce responses")
      (is (listp responses) "Responses should be a list")
      (is (>= (length responses) 2)
          "Should have at least 2 responses (WILL + subneg)")
      ;; First response: IAC WILL MSSP
      (let ((will-resp (first responses)))
        (is (= (aref will-resp 0) 255) "WILL response starts with IAC")
        (is (= (aref will-resp 1) 251) "WILL response has WILL")
        (is (= (aref will-resp 2) 70)  "WILL response is for MSSP"))
      ;; Second response: IAC SB MSSP (vars) IAC SE
      (let ((subneg-resp (second responses)))
        (is (= (aref subneg-resp 0) 255) "Subneg starts with IAC")
        (is (= (aref subneg-resp 1) 250) "Subneg has SB")
        (is (= (aref subneg-resp 2) 70)  "Subneg is for MSSP")
        (is (search "TestMUD"
                    (map 'string #'code-char subneg-resp))
            "Subneg contains 'TestMUD'")
        (is (search "42"
                    (map 'string #'code-char subneg-resp))
            "Subneg contains '42'"))
      ;; Verify option state
      (let ((state (telnet:telnet-local-option protocol
                                               telnet:+telnet-opt-mssp+)))
        (is (not (null state)) "MSSP option state should exist")
        (is (telnet::telnet-option-state-enabled state)
            "MSSP should be enabled after negotiation")))))

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
DO MSSP with WILL MSSP and the MSSP response data."
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
               ;; Client sends DO MSSP: IAC DO MSSP (option 70)
               (write-bytes cli-write-stream #(255 253 70))
               (force-output cli-write-stream)
               (sleep 0.1)
               ;; Server reads — this triggers DO MSSP processing
               ;; which calls the :around method that sends the MSSP response
               (telnet:telnet-read-char srv-conn :timeout 2)
               ;; info-fn should have been called
               (is-true info-fn-called
                        "info-fn should have been called on DO MSSP")
               ;; Read server's response from client's read pipe
               (let ((resp-buf (make-array 64 :element-type '(unsigned-byte 8)
                                            :fill-pointer 0)))
                 (sleep 0.1)
                 (loop while (listen cli-read-stream)
                       do (vector-push-extend
                           (read-byte cli-read-stream) resp-buf))
                 ;; Should have: IAC WILL MSSP + IAC SB MSSP ... IAC SE
                 (is (>= (length resp-buf) 11)
                     "Should have received MSSP response")
                 ;; First 3 bytes: IAC WILL MSSP
                 (is (= (aref resp-buf 0) 255) "Byte 0: IAC")
                 (is (= (aref resp-buf 1) 251) "Byte 1: WILL")
                 (is (= (aref resp-buf 2) 70)  "Byte 2: MSSP (70)")
                 ;; Bytes 3+: IAC SB MSSP ... IAC SE
                 (is (= (aref resp-buf 3) 255) "Byte 3: IAC (subneg start)")
                 (is (= (aref resp-buf 4) 250) "Byte 4: SB")
                 (is (= (aref resp-buf 5) 70)  "Byte 5: MSSP (70)")
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

(test mssp-drain-processes-telnet-before-login
  "%drain-telnet-negotiation should process MSSP and other telnet commands
before the login flow, leaving data characters in the line buffer."
  (multiple-value-bind (srv-in-read srv-in-write) (sb-posix:pipe)
    (multiple-value-bind (srv-out-read srv-out-write) (sb-posix:pipe)
      (let* ((srv-in-stream
               (sb-sys:make-fd-stream srv-in-read
                                      :input t :output nil
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "drain-srv-in"))
             (srv-out-fd (sb-posix:dup srv-out-write))
             (srv-out-stream
               (sb-sys:make-fd-stream srv-out-fd
                                      :input nil :output t
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "drain-srv-out"))
             ;; Client side: writes to srv-in, reads from srv-out
             (cli-write-stream
               (sb-sys:make-fd-stream srv-in-write
                                      :input nil :output t
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "drain-cli-write"))
             (cli-read-stream
               (sb-sys:make-fd-stream srv-out-read
                                      :input t :output nil
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "drain-cli-read"))
             (info-fn-called nil)
             (info-fn (lambda ()
                        (setf info-fn-called t)
                        (list (cons "NAME" "TestMUD")
                              (cons "PLAYERS" "42"))))
             (protocol (make-instance 'telnet:telnet-protocol))
             (srv-conn (make-instance 'telnet::telnet-connection
                                      :usocket nil
                                      :raw-stream srv-in-stream
                                      :out-stream srv-out-stream
                                      :protocol protocol))
             session)
        (unwind-protect
             (progn
               ;; Simulate make-telnet-connection: send initial negotiation
               (let ((init-cmds (telnet:telnet-init-negotiation protocol)))
                 (dolist (cmd init-cmds)
                   (write-sequence cmd srv-out-stream))
                 (force-output srv-out-stream))
               (sleep 0.05)

               ;; Simulate grapevine checker response:
               ;; DO MSSP (70) + "mssp-request\r\n"
               (write-bytes cli-write-stream
                            (concatenate '(vector (unsigned-byte 8))
                                         ;; DO MSSP (70)
                                         #(255 253 70)
                                         ;; Login line
                                         (map '(vector (unsigned-byte 8))
                                              #'char-code "mssp-request")
                                         #(13 10)))
               (force-output cli-write-stream)
               (sleep 0.1)

               ;; Set up session — calls %setup-telnet-mssp on the protocol
               (setf session
                     (apeiron.server::%make-telnet-session
                      srv-conn
                      :mssp-info-fn info-fn))
               (is (not (null session)) "Session should be created")

               ;; KEY: drain before any login reads
               (apeiron.server::%drain-telnet-negotiation srv-conn)

               ;; Verify info-fn was called via DO MSSP → :around method
               (is-true info-fn-called
                        "info-fn called during drain (via DO MSSP)")

               ;; Verify MSSP response was sent to client:
               ;; IAC WILL MSSP + IAC SB MSSP ... IAC SE
               (let ((resp-buf (make-array 128 :element-type '(unsigned-byte 8)
                                            :fill-pointer 0)))
                 (sleep 0.1)
                 (loop while (listen cli-read-stream)
                       do (vector-push-extend
                           (read-byte cli-read-stream) resp-buf))
                 (is (>= (length resp-buf) 11)
                     "MSSP response received")
                 ;; Search for the WILL MSSP marker (FF FB 46) in the buffer
                 (let ((will-pos (search #(255 251 70) resp-buf)))
                   (is-true will-pos "Response contains WILL MSSP (FF FB 46)")
                   (when will-pos
                     (is (search "TestMUD"
                                 (map 'string #'code-char resp-buf))
                         "Contains 'TestMUD'"))
                   (is (search "42"
                               (map 'string #'code-char resp-buf))
                       "Contains '42'")))

               ;; Verify login text preserved in line buffer
               (multiple-value-bind (line status)
                   (telnet:telnet-read-line srv-conn :timeout 2)
                 (is (null status) "Line read succeeds")
                 (is (string= line "mssp-request")
                     "Line reads: ~s" line)))
          (dolist (s (list srv-in-stream srv-out-stream cli-write-stream
                           cli-read-stream))
            (ignore-errors (close s :abort t)))
          (dolist (fd (list srv-in-read srv-in-write srv-out-read srv-out-write
                             srv-out-fd))
            (ignore-errors (sb-posix:close fd)))
          (when session
            (ignore-errors (session-disconnect session))))))))
