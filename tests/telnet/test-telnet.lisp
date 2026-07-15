(in-package #:apeiron-test)

(in-suite telnet-suite)

;; ---------------------------------------------------------------
;; Helpers: create a telnet-connection backed by a pipe,
;; so we can feed controlled bytes and observe responses.
;; ---------------------------------------------------------------

(defun make-test-telnet-connection ()
  "Create a telnet connection backed by a unix pipe instead of a real socket.
Returns (values conn write-stream) where WRITE-STREAM is an output stream
on the write end of the pipe. Feed bytes to the connection by writing
to WRITE-STREAM."
  (multiple-value-bind (read-fd write-stream) (sb-posix:pipe)
    (let* ((raw-stream (sb-sys:make-fd-stream read-fd
                                              :input t :output nil
                                              :element-type '(unsigned-byte 8)
                                              :buffering :none
                                              :name "test-binary-stream"))
           (write-stream (sb-sys:make-fd-stream write-stream
                                                :input nil :output t
                                                :element-type '(unsigned-byte 8)
                                                :buffering :none
                                                :name "test-write-stream"))
           (protocol (make-instance 'telnet::telnet-protocol))
           (conn (make-instance 'telnet::telnet-connection
                                :usocket nil
                                :raw-stream raw-stream
                                :protocol protocol)))
      (values conn write-stream))))

(defun write-bytes (stream bytes)
  "Write all BYTES to STREAM."
  (write-sequence bytes stream)
  (force-output stream))

(defun close-test-connection (conn write-stream)
  "Close the test connection and its pipe."
  (let ((raw (telnet::telnet-conn-raw-stream conn)))
    (when raw (close raw :abort t)))
  (when write-stream (close write-stream :abort t)))

;; ---------------------------------------------------------------
;; Test: telnet-read-char with plain ASCII data (no IAC bytes)
;; ---------------------------------------------------------------

(test telnet-read-char-plain-ascii
  "telnet-read-char should return a character for plain ASCII bytes."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream #(65))  ;; 'A'
           (sleep 0.1)
           (multiple-value-bind (char status)
               (telnet:telnet-read-char conn :timeout 2)
             (is (char= char #\A))
             (is (null status))))
      (close-test-connection conn write-stream))))

;; End of Record (EOR) Protocol Tests  —  RFC 885
;; ===============================================================

;; ----------------------------------------------------------------------
;; Test: EOR option constant value
;; ----------------------------------------------------------------------

(test telnet-eor-option-constant
  "+telnet-opt-eor+ should be 25 per RFC 885."
  (is (= telnet:+telnet-opt-eor+ 25)
      "EOR option code should be 25"))

;; ----------------------------------------------------------------------
;; Test: EOR command code value
;; ----------------------------------------------------------------------

(test telnet-eor-command-code
  "The EOR command code should be 239 (0xEF)."
  (is (= telnet::eor 239)
      "EOR command code should be 239"))

;; ----------------------------------------------------------------------
;; Test: WILL EOR in initial negotiation
;; ----------------------------------------------------------------------

(test telnet-eor-in-init-negotiation
  "telnet-init-negotiation should include WILL EOR (IAC WILL 25)."
  (let* ((protocol (make-instance 'telnet:telnet-protocol))
         (cmds (telnet:telnet-init-negotiation protocol))
         (found-will-eor nil))
    (dolist (cmd cmds)
      (when (and (= (length cmd) 3)
                 (= (aref cmd 0) 255)     ; IAC
                 (= (aref cmd 1) 251)     ; WILL
                 (= (aref cmd 2) 25))     ; EOR
        (setf found-will-eor t)))
    (is-true found-will-eor
             "Init negotiation should include WILL EOR")))

;; ----------------------------------------------------------------------
;; Test: EOR option state after init negotiation
;; ----------------------------------------------------------------------

(test telnet-eor-state-after-init
  "After telnet-init-negotiation, the EOR local option should be
wanted and pending (waiting for the client's DO EOR)."
  (let* ((protocol (make-instance 'telnet:telnet-protocol)))
    (telnet:telnet-init-negotiation protocol)
    (let ((state (telnet:telnet-local-option protocol
                                             telnet:+telnet-opt-eor+)))
      (is-true (not (null state))
               "EOR option state should exist")
      (is-true (telnet::telnet-option-state-wanted state)
               "EOR should be wanted")
      (is-true (telnet::telnet-option-state-pending state)
               "EOR should be pending")
      (is-false (telnet::telnet-option-state-enabled state)
                "EOR should NOT yet be enabled"))))

;; ----------------------------------------------------------------------
;; Test: DO EOR enables the option
;; ----------------------------------------------------------------------

(test telnet-do-eor-enables-option
  "When the client responds DO EOR to our WILL EOR offer,
the option should become enabled and pending cleared."
  (let* ((protocol (make-instance 'telnet:telnet-protocol)))
    (telnet:telnet-init-negotiation protocol)
    ;; Simulate receiving DO EOR
    (telnet:telnet-process-command protocol telnet::do 25)
    (let ((state (telnet:telnet-local-option protocol
                                             telnet:+telnet-opt-eor+)))
      (is-true (telnet::telnet-option-state-enabled state)
               "EOR should be enabled after DO")
      (is-false (telnet::telnet-option-state-pending state)
                "EOR should no longer be pending"))))

;; ----------------------------------------------------------------------
;; Test: DONT EOR disables the option
;; ----------------------------------------------------------------------

(test telnet-dont-eor-disables-option
  "When the client responds DONT EOR (refusing our WILL offer),
the option should not be enabled.  Because the option was never
enabled (still pending), the DONT handler simply records the
refusal without clearing pending."
  (let* ((protocol (make-instance 'telnet:telnet-protocol)))
    (telnet:telnet-init-negotiation protocol)
    ;; Simulate receiving DONT EOR
    (telnet:telnet-process-command protocol telnet::dont 25)
    (let ((state (telnet:telnet-local-option protocol
                                             telnet:+telnet-opt-eor+)))
      (is-false (telnet::telnet-option-state-enabled state)
                "EOR should NOT be enabled after DONT"))))

;; ----------------------------------------------------------------------
;; Test: telnet-send-eor is a no-op when EOR not negotiated
;; ----------------------------------------------------------------------

(test telnet-send-eor-noop-without-negotiation
  "telnet-send-eor should not send any data when EOR has not been
negotiated (the option is not enabled)."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; EOR hasn't been negotiated — telnet-send-eor should be a no-op
           (is-false (telnet:telnet-send-eor conn)
                     "send-eor should return nil when not negotiated"))
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: telnet-send-eor sends correct bytes when negotiated
;; ----------------------------------------------------------------------

(test telnet-send-eor-sends-correct-bytes
  "When EOR has been negotiated (DO EOR received), telnet-send-eor
should send IAC SB EOR IAC SE = #(255 250 25 255 240)."
  (multiple-value-bind (pipe-in-read pipe-in-write) (sb-posix:pipe)
    (multiple-value-bind (pipe-out-read pipe-out-write) (sb-posix:pipe)
      (let* ((in-stream (sb-sys:make-fd-stream pipe-in-read
                                               :input t :output nil
                                               :element-type '(unsigned-byte 8)
                                               :buffering :none
                                               :name "test-eor-input"))
             (out-fd (sb-posix:dup pipe-out-write))
             (out-stream (sb-sys:make-fd-stream out-fd
                                                :input nil :output t
                                                :element-type '(unsigned-byte 8)
                                                :buffering :none
                                                :name "test-eor-output"))
             (in-write-stream
               (sb-sys:make-fd-stream pipe-in-write
                                      :input nil :output t
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "test-eor-in-write"))
             (out-read-stream
               (sb-sys:make-fd-stream pipe-out-read
                                      :input t :output nil
                                      :element-type '(unsigned-byte 8)
                                      :buffering :none
                                      :name "test-eor-out-read"))
             (protocol (make-instance 'telnet::telnet-protocol))
             (conn (make-instance 'telnet::telnet-connection
                                  :usocket nil
                                  :raw-stream in-stream
                                  :out-stream out-stream
                                  :protocol protocol)))
        (unwind-protect
             (let ((read-buf (make-array 5 :element-type '(unsigned-byte 8)
                                          :fill-pointer 0)))
               ;; Enable EOR via negotiation
               (telnet:telnet-init-negotiation protocol)
               (telnet:telnet-process-command protocol telnet::do 25)
               ;; Call telnet-send-eor
               (is-true (telnet:telnet-send-eor conn)
                        "send-eor should return t when negotiated")
               ;; Read the output from the output pipe
               (sleep 0.1)
               (loop while (listen out-read-stream)
                     do (vector-push-extend
                         (read-byte out-read-stream)
                         read-buf))
               ;; Expected: IAC SB EOR IAC SE = 255, 250, 25, 255, 240
               (is (= (length read-buf) 5)
                   "Should have sent exactly 5 bytes")
               (is (= (aref read-buf 0) 255) "Byte 0 should be IAC")
               (is (= (aref read-buf 1) 250) "Byte 1 should be SB")
               (is (= (aref read-buf 2) 25)  "Byte 2 should be EOR option (25)")
               (is (= (aref read-buf 3) 255) "Byte 3 should be IAC")
               (is (= (aref read-buf 4) 240) "Byte 4 should be SE"))
          ;; Cleanup
          (dolist (s (list in-stream out-stream in-write-stream out-read-stream))
            (ignore-errors (close s :abort t)))
          (dolist (fd (list pipe-in-read pipe-in-write pipe-out-read pipe-out-write
                             out-fd))
            (ignore-errors (sb-posix:close fd))))))))

;; ----------------------------------------------------------------------
;; Test: telnet-send-eor returns nil when connection is closed
;; ----------------------------------------------------------------------

(test telnet-send-eor-returns-nil-when-closed
  "telnet-send-eor should return nil when the connection is closed."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (let* ((protocol (telnet::telnet-conn-protocol conn)))
      ;; Enable EOR first
      (telnet:telnet-init-negotiation protocol)
      (telnet:telnet-process-command protocol telnet::do 25)
      ;; Close the connection
      (telnet:telnet-connection-close conn)
      ;; Now telnet-send-eor should return nil
      (is-false (telnet:telnet-send-eor conn)
                "send-eor should return nil when connection is closed"))
    ;; Clean up write stream since conn is already closed
    (when write-stream (close write-stream :abort t))))

;; ----------------------------------------------------------------------
;; Test: telnet-send-eor returns nil when EOR refused (DONT)
;; ----------------------------------------------------------------------

(test telnet-send-eor-returns-nil-when-refused
  "telnet-send-eor should return nil when the client refused EOR (DONT)."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (let ((protocol (telnet::telnet-conn-protocol conn)))
           ;; Client refuses EOR
           (telnet:telnet-process-command protocol telnet::dont 25)
           ;; send-eor should be a no-op
           (is-false (telnet:telnet-send-eor conn)
                     "send-eor should return nil when EOR was refused"))
      (close-test-connection conn write-stream))))

;; ===============================================================
;; Connection Guard Tests
;; ===============================================================

(defun %make-guard-test-socket-pair ()
  (let* ((server (usocket:socket-listen "127.0.0.1" 0 :reuse-address t))
         (port (usocket:get-local-port server)))
    (values server nil port)))

(defun %connect-and-send (port bytes)
  (let ((client (usocket:socket-connect "127.0.0.1" port)))
    (let ((stream (usocket:socket-stream client)))
      (write-sequence bytes stream)
      (force-output stream))
    client))

(test guard-non-telnet-byte-http-get
  (is-true (telnet::%non-telnet-byte-p 71)))

(test guard-non-telnet-byte-http-post
  (is-true (telnet::%non-telnet-byte-p 80)))

(test guard-non-telnet-byte-http-connect
  (is-true (telnet::%non-telnet-byte-p 67)))

(test guard-non-telnet-byte-http-head
  (is-true (telnet::%non-telnet-byte-p 72)))

(test guard-non-telnet-byte-http-delete
  (is-true (telnet::%non-telnet-byte-p 68)))

(test guard-non-telnet-byte-http-options
  (is-true (telnet::%non-telnet-byte-p 79)))

(test guard-non-telnet-byte-http-trace
  (is-true (telnet::%non-telnet-byte-p 84)))

(test guard-non-telnet-byte-http-put
  (is-true (telnet::%non-telnet-byte-p 85)))

(test guard-non-telnet-byte-tls-hello
  (is-true (telnet::%non-telnet-byte-p #x16)))

(test guard-non-telnet-byte-tls-version
  (is-true (telnet::%non-telnet-byte-p 3)))

(test guard-non-telnet-byte-iac
  (is-false (telnet::%non-telnet-byte-p #xFF)))

(test guard-non-telnet-byte-tab
  (is-false (telnet::%non-telnet-byte-p 9)))

(test guard-non-telnet-byte-lf
  (is-false (telnet::%non-telnet-byte-p 10)))

(test guard-non-telnet-byte-cr
  (is-false (telnet::%non-telnet-byte-p 13)))

(test guard-non-telnet-byte-esc
  (is-false (telnet::%non-telnet-byte-p 27)))

(test guard-non-telnet-byte-nul
  (is-true (telnet::%non-telnet-byte-p 0)))

(test guard-non-telnet-byte-lowercase
  (is-false (telnet::%non-telnet-byte-p 97)))

(test guard-non-telnet-byte-high-non-iac
  (is-true (telnet::%non-telnet-byte-p #xFE)))

(test guard-non-telnet-byte-space
  (is-false (telnet::%non-telnet-byte-p 32)))

(test guard-non-telnet-byte-digit
  (is-false (telnet::%non-telnet-byte-p 49)))

(test guard-non-telnet-byte-non-http-method-letter
  (is-false (telnet::%non-telnet-byte-p 70)))
