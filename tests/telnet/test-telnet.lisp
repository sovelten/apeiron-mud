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

(test telnet-read-char-multiple-ascii
  "telnet-read-char should read multiple ASCII bytes in sequence."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream #(65 66 67))  ;; 'ABC'
           (sleep 0.1)
           (multiple-value-bind (c1 s1) (telnet:telnet-read-char conn :timeout 2)
             (is (char= c1 #\A)) (is (null s1)))
           (multiple-value-bind (c2 s2) (telnet:telnet-read-char conn :timeout 2)
             (is (char= c2 #\B)) (is (null s2)))
           (multiple-value-bind (c3 s3) (telnet:telnet-read-char conn :timeout 2)
             (is (char= c3 #\C)) (is (null s3))))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: telnet-read-char with IAC DO option
;; The IAC DO SGA = 255, 253, 3 should be consumed silently
;; ---------------------------------------------------------------

(test telnet-read-char-first-byte-is-iac
  "Verify what telnet-read-char returns for IAC DO SGA."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream #(255 253 3 65))
           (sleep 0.1)
           (multiple-value-bind (c1 s1) (telnet:telnet-read-char conn :timeout 2)
             (format t "~&DEBUG: c1=~S (code=~D) s1=~S~%" c1 (if c1 (char-code c1) nil) s1)
             ;; The BUG: first call should return timeout (IAC consumed),
             ;; but instead returns ÿ (char 255 decoded as Latin-1)
             (is (null c1) "First call should return nil (IAC consumed)"))
           (multiple-value-bind (c2 s2) (telnet:telnet-read-char conn :timeout 2)
             (format t "~&DEBUG: c2=~S s2=~S~%" c2 s2)
             (is (char= c2 #\A) "Second call should return 'A'")))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: telnet-read-char with IAC WILL option
;; ---------------------------------------------------------------

(test telnet-read-char-skips-iac-will-echo
  "telnet-read-char should skip an IAC WILL ECHO negotiation command."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; IAC WILL ECHO = 255, 251, 1
           (write-bytes write-stream #(255 251 1 65))
           (sleep 0.1)
           (multiple-value-bind (c1 s1) (telnet:telnet-read-char conn :timeout 2)
             (is (null c1))
             (is (eq s1 :timeout)))
           (multiple-value-bind (c2 s2) (telnet:telnet-read-char conn :timeout 2)
             (is (char= c2 #\A))
             (is (null s2))))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: telnet-read-char with IAC IAC (literal 255 data byte)
;; 255 as data should be sent as IAC IAC and decoded to char ÿ
;; ---------------------------------------------------------------

(test telnet-read-char-iac-iac-literal-255
  "telnet-read-char should handle IAC IAC as a literal 0xFF data byte."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; IAC IAC = 255 255 = literal 255 byte
           (write-bytes write-stream #(255 255 65))
           (sleep 0.1)
           ;; Should return character with code 255
           (multiple-value-bind (c1 s1) (telnet:telnet-read-char conn :timeout 2)
             (is (not (null c1)))
             (is (= (char-code c1) 255))
             (is (null s1)))
           ;; Then 'A'
           (multiple-value-bind (c2 s2) (telnet:telnet-read-char conn :timeout 2)
             (is (char= c2 #\A))
             (is (null s2))))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: telnet-read-line with plain ASCII
;; ---------------------------------------------------------------

(test telnet-read-line-plain
  "telnet-read-line should return a string for a CR-LF terminated line."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream (concatenate '(vector (unsigned-byte 8))
                                           (flexi-streams:string-to-octets "Hello" :external-format :utf-8)
                                           #(13 10)))
           (sleep 0.1)
           (let* ((start (get-internal-real-time))
                  (result (multiple-value-list (telnet:telnet-read-line conn :timeout 2)))
                  (elapsed (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
             (format t "~&DEBUG: result=~S elapsed=~,2Fs~%" result elapsed)
             (destructuring-bind (line status) result
               (is (string= line "Hello"))
               (is (null status)))))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: telnet-read-line skipping IAC negotiation before data
;; ---------------------------------------------------------------

(test telnet-read-line-skips-initial-negotiation
  "telnet-read-line should skip IAC negotiation commands preceding data."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; Simulate typical initial negotiation: DO SGA, WILL SGA, WILL ECHO
           ;; followed by a line of text
           (write-bytes write-stream (concatenate '(vector (unsigned-byte 8))
                                       ;; Negotiation
                                       #(255 253 3    ;; IAC DO SGA
                                         255 251 3    ;; IAC WILL SGA
                                         255 251 1)   ;; IAC WILL ECHO
                                       ;; Data
                                       (flexi-streams:string-to-octets "What is your name?" :external-format :utf-8)
                                       #(13 10)))
           (sleep 0.1)
           (multiple-value-bind (line status)
               (telnet:telnet-read-line conn :timeout 2)
             (format t "~&DEBUG: line=~S status=~S~%" line status)
             (is (string= line "What is your name?"))
             (is (null status))))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: telnet-write-string and then telnet-read-line roundtrip
;; Uses two test connections connected via a unix socket pair
;; ---------------------------------------------------------------

(test telnet-write-read-roundtrip
  "Write a line through one connection and read it from another."
  (multiple-value-bind (pipe-a-read pipe-a-write) (sb-posix:pipe)
    (multiple-value-bind (pipe-b-read pipe-b-write) (sb-posix:pipe)
      ;; Conn A reads from pipe-a, writes to pipe-b
      ;; Conn B reads from pipe-b, writes to pipe-a
      (let* ((raw-a (sb-sys:make-fd-stream pipe-a-read
                                           :input t :output nil
                                           :element-type '(unsigned-byte 8)
                                           :buffering :none
                                           :name "test-a-input"))
             (out-a-fd (sb-posix:dup pipe-b-write))
             (raw-a-out (sb-sys:make-fd-stream out-a-fd
                                               :input nil :output t
                                               :element-type '(unsigned-byte 8)
                                               :buffering :none
                                               :name "test-a-output"))
             (raw-b (sb-sys:make-fd-stream pipe-b-read
                                           :input t :output nil
                                           :element-type '(unsigned-byte 8)
                                           :buffering :none
                                           :name "test-b-input"))
             (out-b-fd (sb-posix:dup pipe-a-write))
             (raw-b-out (sb-sys:make-fd-stream out-b-fd
                                               :input nil :output t
                                               :element-type '(unsigned-byte 8)
                                               :buffering :none
                                               :name "test-b-output"))
             (proto-a (make-instance 'telnet::telnet-protocol))
             (proto-b (make-instance 'telnet::telnet-protocol))
             (conn-a (make-instance 'telnet::telnet-connection
                                    :usocket nil
                                    :raw-stream raw-a
                                    :out-stream raw-a-out
                                    :protocol proto-a))
             (conn-b (make-instance 'telnet::telnet-connection
                                    :usocket nil
                                    :raw-stream raw-b
                                    :out-stream raw-b-out
                                    :protocol proto-b)))
        (unwind-protect
             (progn
               (telnet:telnet-write-string conn-a "Hello from A" :end :crlf)
               (sleep 0.1)
               (multiple-value-bind (line status)
                   (telnet:telnet-read-line conn-b :timeout 2)
                 (format t "~&DEBUG roundtrip: line=~S status=~S~%" line status)
                 (is (string= line "Hello from A"))
                 (is (null status))))
          (dolist (s (list raw-a raw-a-out raw-b raw-b-out))
            (when s (close s :abort t)))
          (dolist (fd (list pipe-a-read pipe-a-write pipe-b-read pipe-b-write
                             out-a-fd out-b-fd))
            (ignore-errors (sb-posix:close fd))))))))

;; ---------------------------------------------------------------
;; Test: minimal-telnet-test — original raw socket binary test
;; ---------------------------------------------------------------

(test minimal-telnet-test
  (let* ((server (usocket:socket-listen "127.0.0.1" 0 :reuse-address t))
         (port (usocket:get-local-port server)))

    (bt:make-thread
     (lambda ()
       (handler-case
           (let* ((accepted (usocket:socket-accept server))
                  (native (usocket:socket accepted))
                  (old-fd (sb-bsd-sockets:socket-file-descriptor native))
                  (new-fd (sb-posix:dup old-fd))
                  (binary (sb-sys:make-fd-stream new-fd
                                                 :input t :output t
                                                 :element-type '(unsigned-byte 8)
                                                 :buffering :full
                                                 :name "server-binary")))
             (write-sequence #(#x41 #x42 #x43) binary)
             (force-output binary)
             (sleep 3)
             (close binary)
             (usocket:socket-close accepted))
         (error (e)
           (format t "Server error: ~A~%" e)
           (finish-output))))
     :name "test-server")

    (sleep 0.4)

    (let* ((client-socket (usocket:socket-connect "127.0.0.1" port))
           (native (usocket:socket client-socket))
           (old-fd (sb-bsd-sockets:socket-file-descriptor native))
           (new-fd (sb-posix:dup old-fd))
           (binary (sb-sys:make-fd-stream new-fd
                                          :input t :output t
                                          :element-type '(unsigned-byte 8)
                                          :buffering :full
                                          :name "client-binary")))
      (let* ((timeout 2.0)
             (deadline (+ (get-internal-real-time)
                          (* timeout internal-time-units-per-second)))
             (ready nil)
             (buf (make-array 3 :element-type '(unsigned-byte 8))))
        (loop
          (when (listen binary)
            (setf ready t)
            (return))
          (let ((remaining (- deadline (get-internal-real-time))))
            (when (<= remaining 0)
              (return)))
          (sleep 0.05))

        (is (not (null ready))
            "Client should have received data within 2s timeout")

        (when ready
          (read-sequence buf binary)
          (is (equalp buf #(#x41 #x42 #x43))
              "Received bytes should equal #(65 66 67) = ABC")))

      (close binary)
      (usocket:socket-close client-socket))

    (sleep 0.3)
    (usocket:socket-close server)))

;; ---------------------------------------------------------------
;; Test: multi-byte UTF-8 decoding
;; ---------------------------------------------------------------

(test telnet-read-line-utf8-multibyte
  "telnet-read-line should correctly decode multi-byte UTF-8 characters."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (concatenate '(vector (unsigned-byte 8))
                                     (flexi-streams:string-to-octets
                                      "café ☕ über" :external-format :utf-8)
                                     #(13 10)))
           (sleep 0.1)
           (multiple-value-bind (line status)
               (telnet:telnet-read-line conn :timeout 2)
             (is (string= line "café ☕ über"))
             (is (null status))))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: a multi-byte UTF-8 char split across separate reads
;; ---------------------------------------------------------------

(test telnet-read-line-utf8-split-across-reads
  "A multi-byte UTF-8 character split across separate reads should decode."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (let ((bytes (flexi-streams:string-to-octets "é" :external-format :utf-8)))
           ;; é = #xC3 #xA9: send the lead byte, pause, then continuation + CRLF.
           (write-bytes write-stream (subseq bytes 0 1))
           (sleep 0.15)
           (write-bytes write-stream
                        (concatenate '(vector (unsigned-byte 8))
                                     (subseq bytes 1)
                                     #(13 10)))
           (sleep 0.1)
           (multiple-value-bind (line status)
               (telnet:telnet-read-line conn :timeout 2)
             (is (string= line "é"))
             (is (null status))))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: a bare LF (no CR) terminates a line
;; ---------------------------------------------------------------

(test telnet-read-line-bare-lf
  "telnet-read-line should accept a bare LF (no preceding CR) as a terminator."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (concatenate '(vector (unsigned-byte 8))
                                     (flexi-streams:string-to-octets
                                      "bare line" :external-format :utf-8)
                                     #(10)))
           (sleep 0.1)
           (multiple-value-bind (line status)
               (telnet:telnet-read-line conn :timeout 2)
             (is (string= line "bare line"))
             (is (null status))))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: NAWS subnegotiation updates window dimensions
;; ---------------------------------------------------------------

(test telnet-naws-subnegotiation-updates-window
  "NAWS subnegotiation should update the protocol's window dimensions."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (let ((proto (telnet::telnet-conn-protocol conn)))
           ;; IAC SB NAWS width=132 height=43 IAC SE
           (write-bytes write-stream #(255 250 31 0 132 0 43 255 240))
           (sleep 0.1)
           ;; A single telnet-read-char consumes the whole subnegotiation.
           (telnet:telnet-read-char conn :timeout 2)
           (is (= (telnet:telnet-window-width proto) 132))
           (is (= (telnet:telnet-window-height proto) 43)))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: TERMINAL-TYPE subnegotiation updates the reported terminal
;; ---------------------------------------------------------------

(test telnet-terminal-type-subnegotiation
  "TERMINAL-TYPE IS subnegotiation should update the reported terminal type."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (let ((proto (telnet::telnet-conn-protocol conn)))
           ;; IAC SB TERMINAL-TYPE IS "XTERM" IAC SE  (24 = TTYPE, 0 = IS)
           (write-bytes write-stream
                        (concatenate '(vector (unsigned-byte 8))
                                     #(255 250 24 0)
                                     (map '(vector (unsigned-byte 8))
                                          #'char-code "XTERM")
                                     #(255 240)))
           (sleep 0.1)
           (telnet:telnet-read-char conn :timeout 2)
           (is (string= (telnet:telnet-terminal-type proto) "XTERM")))
      (close-test-connection conn write-stream))))

;; ---------------------------------------------------------------
;; Test: IAC escaping logic (doubling of 255 bytes)
;; ---------------------------------------------------------------

(test telnet-iac-escape-doubles-iac
  "iac-escape should double every IAC (255) byte and leave others intact."
  (is (equalp (telnet::iac-escape
               (coerce #(1 255 2 255 255 3) '(vector (unsigned-byte 8))))
              (coerce #(1 255 255 2 255 255 255 255 3)
                      '(vector (unsigned-byte 8)))))
  (is (= (telnet::iac-escape-length
          (coerce #(255 255) '(vector (unsigned-byte 8))))
         4))
  (is (= (telnet::iac-escape-length
          (coerce #(1 2 3) '(vector (unsigned-byte 8))))
         3)))

;; ---------------------------------------------------------------
;; Test: EOF detection when the peer closes the connection
;; ---------------------------------------------------------------

(test telnet-read-char-eof
  "telnet-read-char should promptly return (nil :eof) when the peer closes."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; Close the write end so the read end observes end-of-file.
           (close write-stream :abort nil)
           (sleep 0.1)
           (multiple-value-bind (c status)
               (telnet:telnet-read-char conn :timeout 2)
             (is (null c))
             (is (eq status :eof))
             (is (null (telnet:telnet-connection-alive-p conn)))))
      ;; write-stream is already closed; close the raw read stream only.
      (let ((raw (telnet::telnet-conn-raw-stream conn)))
        (when raw (ignore-errors (close raw :abort t)))))))

;; ===============================================================
;; TLS Support Tests
;; ===============================================================

;; ----------------------------------------------------------------------
;; Test: telnet-tls-connection-p returns nil for plain connections
;; ----------------------------------------------------------------------

(test telnet-tls-connection-p-plain-returns-nil
  "telnet-tls-connection-p should return nil for a plain (non-TLS) connection."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (is (not (telnet:telnet-tls-connection-p conn)))
           "Plain connection should not be recognized as TLS")
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: telnet-register-start-tls registers the option
;; ----------------------------------------------------------------------

(test telnet-register-start-tls-registers-option
  "telnet-register-start-tls should mark the START_TLS option as wanted."
  (let ((protocol (telnet:telnet-register-start-tls
                   (make-instance 'telnet:telnet-protocol))))
    (let ((state (telnet:telnet-local-option protocol
                                             telnet:+telnet-opt-start-tls+)))
      (is (not (null state))
          "START_TLS option state should exist")
      (is (telnet::telnet-option-state-wanted state)
          "START_TLS should be wanted")
      (is (telnet::telnet-option-state-pending state)
          "START_TLS should be pending"))))

;; ----------------------------------------------------------------------
;; Test: START_TLS included in init negotiation when registered
;; ----------------------------------------------------------------------

(test telnet-start-tls-appears-in-init-negotiation
  "When START_TLS is registered, the init negotiation should include
WILL START_TLS (IAC WILL 46)."
  (let* ((protocol (telnet:telnet-register-start-tls
                    (make-instance 'telnet:telnet-protocol)))
         (cmds (telnet:telnet-init-negotiation protocol))
         (found-will-start-tls nil))
    (dolist (cmd cmds)
      ;; Look for IAC WILL 46 = #(255 251 46)
      (when (and (= (length cmd) 3)
                 (= (aref cmd 0) 255)     ; IAC
                 (= (aref cmd 1) 251)     ; WILL
                 (= (aref cmd 2) 46))     ; START_TLS
        (setf found-will-start-tls t)))
    (is-true found-will-start-tls
             "Init negotiation should include WILL START_TLS")))

;; ----------------------------------------------------------------------
;; Test: DO START_TLS does not produce a response
;; ----------------------------------------------------------------------

(test telnet-do-start-tls-produces-no-response
  "When we receive DO START_TLS (client accepting our WILL offer),
the :around method should return NIL so no telnet response is sent."
  (let* ((protocol (telnet:telnet-register-start-tls
                    (make-instance 'telnet:telnet-protocol)))
         ;; Simulate receiving DO START_TLS
         (responses (telnet:telnet-process-command
                     protocol
                     telnet::do        ; DO = 253
                     46)))               ; START_TLS option
    (is (null responses)
        "DO START_TLS should produce no telnet response bytes")))

;; ----------------------------------------------------------------------
;; Test: make-telnet-connection accepts custom protocol with START_TLS
;; ----------------------------------------------------------------------

(test telnet-make-connection-with-start-tls-protocol
  "make-telnet-connection should accept a pre-configured protocol that
has START_TLS registered."
  (let* ((protocol (telnet:telnet-register-start-tls
                    (make-instance 'telnet:telnet-protocol)))
         (server (usocket:socket-listen "127.0.0.1" 0 :reuse-address t))
         (port (usocket:get-local-port server))
         conn)
    (unwind-protect
         (let ((server-thread
                 (bt:make-thread
                  (lambda ()
                    (handler-case
                        (let ((accepted (usocket:socket-accept server)))
                          (setf conn
                                (telnet:make-telnet-connection
                                 accepted
                                 :protocol protocol)))
                      (error (e)
                        (format t "~&Server error: ~A~%" e))))
                  :name "tls-protocol-test")))
           (sleep 0.2)
           ;; Connect a client to trigger the server accept
           (let ((client (usocket:socket-connect "127.0.0.1" port)))
             (sleep 0.3)
             (usocket:socket-close client))
           (bt:join-thread server-thread)
           (is (not (null conn)) "Connection should be created")
           (when conn
             ;; Verify the protocol has START_TLS registered
             (let ((state (telnet:telnet-local-option
                           (telnet::telnet-conn-protocol conn)
                           telnet:+telnet-opt-start-tls+)))
               (is (not (null state))
                   "Connection protocol should have START_TLS state")
               (is (telnet::telnet-option-state-wanted state)
                   "START_TLS should be wanted on created connection"))))
      (when conn
        (ignore-errors (telnet:telnet-connection-close conn)))
      (when server
        (ignore-errors (usocket:socket-close server))))))

;; ----------------------------------------------------------------------
;; Test: TLS connection with self-signed cert (requires OpenSSL CLI)
;; ----------------------------------------------------------------------

(test telnet-tls-connect-with-self-signed-cert
  "Test TLS connection with a generated self-signed certificate.
Requires OpenSSL command-line tool to be installed."
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory)
                                     "mud-test-tls/")))
    (unwind-protect
         (let* ((cert-path (merge-pathnames "cert.pem" temp-dir))
                (key-path (merge-pathnames "key.pem" temp-dir)))
           ;; Generate a self-signed cert using OpenSSL
           (ensure-directories-exist temp-dir)
           (multiple-value-bind (stdout stderr exit)
               (uiop:run-program
                (list "openssl" "req" "-x509"
                      "-newkey" "rsa:2048"
                      "-keyout" (namestring key-path)
                      "-out" (namestring cert-path)
                      "-days" "1"
                      "-nodes"
                      "-subj" "/CN=localhost/O=MUD-Test")
                :output nil
                :ignore-error-status t)
             (declare (ignore stdout stderr))
             (unless (= exit 0)
               (skip "OpenSSL not available for cert generation"))
             (format t "~&Generated test cert at ~A~%" cert-path)
             ;; Set up a TLS server and client
             (let* ((server (usocket:socket-listen
                             "127.0.0.1" 0 :reuse-address t))
                    (port (usocket:get-local-port server))
                    (server-conn nil)
                    (client-data nil)
                    (server-error nil))
               (unwind-protect
                    (progn
                      ;; Server thread: accept and create TLS connection
                      (let ((server-thread
                              (bt:make-thread
                               (lambda ()
                                 (handler-case
                                     (let* ((accepted
                                             (usocket:socket-accept
                                              server)))
                                       (setf server-conn
                                             (telnet:make-telnet-tls-connection
                                              accepted
                                              :certificate
                                              (namestring cert-path)
                                              :key
                                              (namestring key-path))))
                                   (error (e)
                                     (setf server-error e)
                                     (format t "~&Server error: ~A~%" e))))
                               :name "tls-test-server")))
                        ;; Let the server start accepting
                        (sleep 0.3)
                        ;; Client: connect via CL+SSL.
                        ;; Keep socket/stream variables outside the
                        ;; handler-case so cleanup can always reach them.
                        (let ((client-sock nil)
                              (ssl-client nil))
                          (handler-case
                              (progn
                                (setf client-sock
                                      (usocket:socket-connect
                                       "127.0.0.1" port))
                                (let ((client-stream
                                        (usocket:socket-stream
                                         client-sock)))
                                  (setf ssl-client
                                        (cl+ssl:make-ssl-client-stream
                                         client-stream
                                         :verify nil))
                                  (write-sequence
                                   (telnet::iac-escape
                                    (telnet::make-command-2
                                     telnet::do
                                     telnet:+telnet-opt-suppress-go-ahead+))
                                   ssl-client)
                                  (force-output ssl-client)
                                  (setf client-data :ok)))
                            (error (e)
                              (setf client-data e)))
                          ;; Always join the server thread before
                          ;; closing the client, so the server has
                          ;; time to finish its encrypted init
                          ;; negotiation without getting a RST.
                          (bt:join-thread server-thread)
                          ;; Now clean up client resources
                          (when ssl-client
                            (ignore-errors (close ssl-client)))
                          (when client-sock
                            (ignore-errors
                             (usocket:socket-close client-sock)))))
                      ;; Verify results
                      (is (null server-error)
                          (format nil "Server should not error: ~A"
                                  server-error))
                      (is (eq client-data :ok)
                          (format nil "Client should connect via TLS: ~A"
                                  client-data))
                      (is (telnet:telnet-tls-connection-p server-conn)
                          "Server connection should report TLS active"))
                 ;; Cleanup
                 (when server-conn
                   (ignore-errors
                    (telnet:telnet-connection-close server-conn)))
                 (when server
                   (ignore-errors (usocket:socket-close server))))))
      ;; Clean up temp dir
      (ignore-errors
        (uiop:delete-directory-tree temp-dir
                                    :validate (constantly t)
                                    :if-does-not-exist :ignore))))))


;; ===============================================================
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
;; Connection Validation Tests — telnet-validate-connection
;; ===============================================================

;; ----------------------------------------------------------------------
;; Test: HTTP GET request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-get
  "telnet-validate-connection should return NIL and close the connection
when an HTTP GET request arrives on the telnet port."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; Write an HTTP GET request
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "GET / HTTP/1.1"))
           (sleep 0.1)
           (let ((result (telnet:telnet-validate-connection conn :timeout 2)))
             (is-false result
                       "HTTP GET request should be rejected"))
           ;; Connection should be marked as dead
           (is-false (telnet:telnet-connection-alive-p conn)
                     "Connection should be closed after HTTP rejection"))
      ;; conn may already be closed by validate-connection
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: HTTP POST request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-post
  "telnet-validate-connection should reject HTTP POST requests."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "POST /login HTTP/1.1"))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "HTTP POST request should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: HTTP CONNECT request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-connect
  "telnet-validate-connection should reject HTTP CONNECT (proxy) requests."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "CONNECT 10.0.0.1:443 HTTP/1.1"))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "HTTP CONNECT request should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: HTTP HEAD request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-head
  "telnet-validate-connection should reject HTTP HEAD requests."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "HEAD / HTTP/1.0"))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "HTTP HEAD request should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: HTTP PUT request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-put
  "telnet-validate-connection should reject HTTP PUT requests."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "PUT /resource HTTP/1.1"))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "HTTP PUT request should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: HTTP DELETE request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-delete
  "telnet-validate-connection should reject HTTP DELETE requests."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "DELETE /obj/42 HTTP/1.1"))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "HTTP DELETE request should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: HTTP OPTIONS request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-options
  "telnet-validate-connection should reject HTTP OPTIONS requests."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "OPTIONS * HTTP/1.1"))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "HTTP OPTIONS request should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: HTTP PATCH request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-patch
  "telnet-validate-connection should reject HTTP PATCH requests."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "PATCH /data HTTP/1.1"))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "HTTP PATCH request should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: HTTP TRACE request is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-http-trace
  "telnet-validate-connection should reject HTTP TRACE requests."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "TRACE / HTTP/1.1"))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "HTTP TRACE request should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: TLS ClientHello is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-tls-clienthello
  "telnet-validate-connection should reject TLS ClientHello (0x16 0x03)."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; TLS record header: 0x16 = handshake, 0x03 0x01 = TLS 1.0
           (write-bytes write-stream #(#x16 #x03 #x01 #x00 #x00 #x00))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "TLS ClientHello should be rejected")
           (is-false (telnet:telnet-connection-alive-p conn)
                     "Connection should be closed after TLS rejection"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: TLS 1.2 ClientHello is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-tls12-clienthello
  "telnet-validate-connection should reject TLS 1.2 ClientHello (0x16 0x03 0x03)."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; TLS 1.2 record header: 0x16 = handshake, 0x03 0x03 = TLS 1.2
           (write-bytes write-stream #(#x16 #x03 #x03))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "TLS 1.2 ClientHello should be rejected"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: RDP/TPKT is rejected
;; ----------------------------------------------------------------------

(test telnet-validate-rejects-rdp-tpkt
  "telnet-validate-connection should reject RDP/TPKT connections (0x03 0x00)."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; TPKT header: version 3, reserved = 0
           (write-bytes write-stream #(#x03 #x00 #x00 #x00))
           (sleep 0.1)
           (is-false (telnet:telnet-validate-connection conn :timeout 2)
                     "RDP/TPKT connection should be rejected")
           (is-false (telnet:telnet-connection-alive-p conn)
                     "Connection should be closed after RDP rejection"))
      (ignore-errors (close-test-connection conn write-stream)))))

;; ----------------------------------------------------------------------
;; Test: Telnet IAC response is accepted
;; ----------------------------------------------------------------------

(test telnet-validate-accepts-iac-response
  "telnet-validate-connection should accept a connection whose first
byte is IAC (0xFF), indicating a proper telnet negotiation response."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; IAC DO SGA = telnet client responding to our WILL SGA
           (write-bytes write-stream #(#xFF #xFD #x03))
           (sleep 0.1)
           (is-true (telnet:telnet-validate-connection conn :timeout 2)
                    "Telnet IAC response should be accepted")
           ;; Connection should still be alive
           (is-true (telnet:telnet-connection-alive-p conn)
                    "Connection should remain alive after telnet response")
           ;; Peek-buffer should contain the IAC bytes for subsequent reads
           (let ((peek (slot-value conn 'telnet::peek-buffer)))
             (is (= (fill-pointer peek) 3)
                 "Peek-buffer should have 3 bytes (IAC DO SGA)")
             (is (= (aref peek 0) #xFF) "First peek byte should be IAC")))
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: Plain text / raw TCP is accepted
;; ----------------------------------------------------------------------

(test telnet-validate-accepts-plain-text
  "telnet-validate-connection should accept a connection sending plain
text (simulating a raw-TCP / netcat client)."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; Plain ASCII text (lowercase = not an HTTP method)
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "hello server"))
           (sleep 0.1)
           (is-true (telnet:telnet-validate-connection conn :timeout 2)
                    "Plain text should be accepted (raw TCP client)")
           (is-true (telnet:telnet-connection-alive-p conn)
                    "Connection should remain alive")
           ;; Peek-buffer should contain the text bytes
           (let ((peek (slot-value conn 'telnet::peek-buffer)))
             (is (> (fill-pointer peek) 0)
                 "Peek-buffer should contain the pre-read text bytes")))
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: Timeout (no data) is accepted
;; ----------------------------------------------------------------------

(test telnet-validate-accepts-timeout
  "telnet-validate-connection should return T when no data arrives
within the timeout, allowing slow clients to connect."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; Don't write anything - simulate a client that hasn't sent yet
           (is-true (telnet:telnet-validate-connection conn :timeout 0.3)
                    "Timeout with no data should be accepted (slow client)")
           (is-true (telnet:telnet-connection-alive-p conn)
                    "Connection should remain alive after timeout"))
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: Validation drains into peek-buffer for correct subsequent reads
;; ----------------------------------------------------------------------

(test telnet-validate-peek-buffer-drain
  "After successful validation, the peek-buffer bytes should be consumed
by telnet-read-char in the correct order."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; Write some data that will pass validation
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "ABCD"))
           (sleep 0.1)
           ;; Validate - should pass (plain text)
           (is-true (telnet:telnet-validate-connection conn :timeout 2))
           ;; Now read chars via telnet-read-char: they should come from
           ;; the peek-buffer in order
           (multiple-value-bind (c1 s1)
               (telnet:telnet-read-char conn :timeout 1)
             (is (and c1 (char= c1 #\A))
                 "First char from peek-buffer should be 'A'")
             (is (null s1)))
           (multiple-value-bind (c2 s2)
               (telnet:telnet-read-char conn :timeout 1)
             (is (and c2 (char= c2 #\B))
                 "Second char from peek-buffer should be 'B'")
             (is (null s2)))
           (multiple-value-bind (c3 s3)
               (telnet:telnet-read-char conn :timeout 1)
             (is (and c3 (char= c3 #\C))
                 "Third char from peek-buffer should be 'C'")
             (is (null s3)))
           (multiple-value-bind (c4 s4)
               (telnet:telnet-read-char conn :timeout 1)
             (is (and c4 (char= c4 #\D))
                 "Fourth char from peek-buffer should be 'D'")
             (is (null s4))))
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: HTTP partial method not followed by space is NOT rejected
;; ----------------------------------------------------------------------

(test telnet-validate-does-not-false-positive-on-words
  "telnet-validate-connection should NOT reject text that starts with
HTTP-method-like letters but is not actually an HTTP request (no space
after the method word). This prevents false positives on real user input."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; "GetOut" starts with 'G' like GET but has no space - should pass
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "GetOut"))
           (sleep 0.1)
           (is-true (telnet:telnet-validate-connection conn :timeout 2)
                    "Text starting with 'G' without space should NOT be rejected"))
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: Non-HTTP uppercase text (like a player name) is accepted
;; ----------------------------------------------------------------------

(test telnet-validate-accepts-uppercase-name
  "telnet-validate-connection should accept a connection whose first
word starts with uppercase and looks like a player name, not an HTTP method."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; "Gandalf" starts with 'G' but is a name, not an HTTP method
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "Gandalf"))
           (sleep 0.1)
           (is-true (telnet:telnet-validate-connection conn :timeout 2)
                    "Player name starting with uppercase should be accepted"))
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: Single-byte IAC is accepted
;; ----------------------------------------------------------------------

(test telnet-validate-accepts-single-iac
  "telnet-validate-connection should accept a connection whose only
first byte is IAC (0xFF)."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream #(#xFF))
           (sleep 0.1)
           (is-true (telnet:telnet-validate-connection conn :timeout 2)
                    "Single IAC byte should be accepted as telnet"))
      (close-test-connection conn write-stream))))

;; ----------------------------------------------------------------------
;; Test: Empty peek-buffer after validation clears it
;; ----------------------------------------------------------------------

(test telnet-validate-clears-peek-buffer-first
  "telnet-validate-connection should clear the peek-buffer before filling
it, so stale data from a previous call does not remain."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           ;; Manually put junk in the peek-buffer
           (let ((peek (slot-value conn 'telnet::peek-buffer)))
             (vector-push-extend #xFF peek)
             (vector-push-extend #xFF peek))
           ;; Now write actual data for validation
           (write-bytes write-stream
                        (map '(vector (unsigned-byte 8)) #'char-code
                             "X"))
           (sleep 0.1)
           (is-true (telnet:telnet-validate-connection conn :timeout 2)
                    "Validation should pass")
           ;; Peek-buffer should contain only the new data
           (let ((peek (slot-value conn 'telnet::peek-buffer)))
             (is (= (fill-pointer peek) 1)
                 "Peek-buffer should have 1 byte after clearing")
             (is (char= (code-char (aref peek 0)) #\X)
                 "Peek-buffer should contain the new byte, not stale data")))
      (close-test-connection conn write-stream))))
