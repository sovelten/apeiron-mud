(in-package #:mud-test)

(in-suite mud-tests)

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
