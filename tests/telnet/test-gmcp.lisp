;;;; tests/telnet/test-gmcp.lisp — GMCP (Generic Mud Communication Protocol)
;;;;
;;;; Unit tests for the generic, application-independent GMCP layer in the
;;;; telnet package.  These tests never touch game state — they exercise
;;;; only framing, negotiation, dispatch and the send API.

(in-package #:apeiron-test)

(in-suite telnet-suite)

;; ─── Test connection that captures everything written ───────────────────────

(defclass gmcp-test-connection (telnet:telnet-connection)
  ((sent :initform (make-array 0 :element-type '(unsigned-byte 8)
                                 :adjustable t :fill-pointer 0)
         :accessor gmcp-test-sent
         :documentation "Every byte written via telnet-write-raw."))
  (:default-initargs
   :usocket nil
   :raw-stream (make-broadcast-stream)
   :protocol (make-instance 'telnet:telnet-protocol))
  (:documentation "A telnet connection that records outgoing raw bytes."))

(defmethod telnet:telnet-write-raw ((conn gmcp-test-connection) byte-vector)
  (loop for b across byte-vector
        do (vector-push-extend b (gmcp-test-sent conn))))

(defun gmcp-sent-string (conn)
  "Decode the bytes captured so far into a string."
  (map 'string #'code-char (gmcp-test-sent conn)))

(defun gmcp-payload-of-command (bytes)
  "Extract the GMCP payload from a full IAC SB GMCP ... IAC SE command."
  (subseq bytes 3 (- (length bytes) 2)))

(defun enable-gmcp-on (protocol)
  "Force GMCP to the enabled state on PROTOCOL (simulating DO GMCP)."
  (setf (telnet::telnet-option-state-enabled
         (telnet::ensure-option-state protocol :local telnet:+telnet-opt-gmcp+))
        t)
  protocol)

;; ─── Constants ──────────────────────────────────────────────────────────────

(test gmcp-option-constant
  "GMCP is telnet option 201."
  (is (= telnet:+telnet-opt-gmcp+ 201)
      "GMCP option code should be 201"))

;; ─── Framing ────────────────────────────────────────────────────────────────

(test gmcp-encode-framing-with-data
  "gmcp-encode produces IAC SB GMCP <header> <data> IAC SE."
  (let* ((bytes (telnet:gmcp-encode "Char" "Vitals" "{\"hp\":42}"))
         (len (length bytes))
         (text (map 'string #'code-char bytes)))
    (is (= (aref bytes 0) 255) "Byte 0: IAC")
    (is (= (aref bytes 1) 250) "Byte 1: SB")
    (is (= (aref bytes 2) 201) "Byte 2: GMCP")
    (is (= (aref bytes (- len 2)) 255) "Penultimate byte: IAC")
    (is (= (aref bytes (1- len)) 240) "Final byte: SE")
    (is (string= (subseq text 3 (- len 2))
                 "Char.Vitals {\"hp\":42}")
        "Payload is 'Package.Message data'")))

(test gmcp-encode-header-only
  "gmcp-encode with no data emits just the header (no trailing space)."
  (let* ((bytes (telnet:gmcp-encode "Core" "Ping"))
         (text (map 'string #'code-char bytes)))
    (is (string= (subseq text 3 (- (length bytes) 2)) "Core.Ping"))))

(test gmcp-decode-roundtrip
  "gmcp-decode splits header and payload."
  (multiple-value-bind (package message data)
      (telnet:gmcp-decode
       (flexi-streams:string-to-octets "Char.Vitals {\"hp\":42}"
                                       :external-format :utf-8))
    (is (string= package "Char"))
    (is (string= message "Vitals"))
    (is (string= data "{\"hp\":42}"))))

(test gmcp-decode-header-only-has-nil-data
  "gmcp-decode returns NIL data when the message carries no payload."
  (multiple-value-bind (package message data)
      (telnet:gmcp-decode
       (flexi-streams:string-to-octets "Core.Supports.Set"
                                       :external-format :utf-8))
    (is (string= package "Core"))
    (is (string= message "Supports.Set"))
    (is (null data))))

(test gmcp-encode-decode-via-payload
  "A message encoded and then decoded round-trips through the framing."
  (let* ((bytes (telnet:gmcp-encode "Char" "Stats" "{\"str\":10}"))
         (payload (gmcp-payload-of-command bytes)))
    (multiple-value-bind (package message data) (telnet:gmcp-decode payload)
      (is (string= package "Char"))
      (is (string= message "Stats"))
      (is (string= data "{\"str\":10}")))))

;; ─── Negotiation ────────────────────────────────────────────────────────────

(test gmcp-will-in-init-negotiation
  "When GMCP is registered, telnet-init-negotiation includes IAC WILL 201."
  (let* ((protocol (telnet:telnet-register-gmcp
                    (make-instance 'telnet:telnet-protocol)))
         (cmds (telnet:telnet-init-negotiation protocol))
         (found nil))
    (dolist (cmd cmds)
      (when (and (= (length cmd) 3)
                 (= (aref cmd 0) 255)
                 (= (aref cmd 1) 251)
                 (= (aref cmd 2) 201))
        (setf found t)))
    (is-true found "Init negotiation should include WILL GMCP")))

(test gmcp-do-enables-and-handshakes
  "DO GMCP enables the option and returns WILL plus the Core.Hello handshake."
  (let* ((protocol (telnet:telnet-register-gmcp
                    (make-instance 'telnet:telnet-protocol)))
         (responses (telnet:telnet-process-command protocol telnet::do 201))
         (state (telnet:telnet-local-option protocol telnet:+telnet-opt-gmcp+))
         (text (map 'string #'code-char
                    (reduce (lambda (a b) (concatenate '(vector (unsigned-byte 8)) a b))
                            responses))))
    (is-true (telnet::telnet-option-state-enabled state)
             "GMCP should be enabled after DO GMCP")
    (is-true (search (map 'string #'code-char (list 255 251 201)) text)
             "Response should contain WILL GMCP")
    (is-true (search "Core.Hello" text)
             "Response should contain the Core.Hello handshake")))

(test gmcp-do-runs-on-enable-callback
  "The on-enable callback's messages are appended after the handshake."
  (let* ((protocol (telnet:telnet-register-gmcp
                    (make-instance 'telnet:telnet-protocol))))
    (setf (telnet:telnet-gmcp-on-enable-fn protocol)
          (lambda (p) (declare (ignore p))
            (list (list "Core" "Supports.Set" "[\"Char 1\"]"))))
    (let* ((responses (telnet:telnet-process-command protocol telnet::do 201))
           (text (map 'string #'code-char
                      (reduce (lambda (a b)
                                (concatenate '(vector (unsigned-byte 8)) a b))
                              responses))))
      (is-true (search "Core.Supports.Set" text)
               "On-enable messages should be sent")
      (is-true (search "Char 1" text)
               "Core.Supports.Set should advertise the Char package"))))

;; ─── Sending ────────────────────────────────────────────────────────────────

(test gmcp-send-is-noop-when-not-negotiated
  "telnet-send-gmcp returns NIL and writes nothing before negotiation."
  (let* ((protocol (make-instance 'telnet:telnet-protocol))
         (conn (make-instance 'gmcp-test-connection :protocol protocol)))
    (is (null (telnet:telnet-send-gmcp conn "Char" "Vitals" "{\"hp\":1}")))
    (is (= 0 (length (gmcp-test-sent conn)))
        "No bytes should be written when GMCP is not negotiated")))

(test gmcp-send-writes-when-enabled
  "telnet-send-gmcp writes a framed GMCP message once enabled."
  (let* ((protocol (enable-gmcp-on (make-instance 'telnet:telnet-protocol)))
         (conn (make-instance 'gmcp-test-connection :protocol protocol)))
    (is (telnet:telnet-send-gmcp conn "Char" "Vitals" "{\"hp\":1}"))
    (let ((text (gmcp-sent-string conn)))
      (is-true (search "Char.Vitals" text))
      (is-true (search "{\"hp\":1}" text)))))

;; ─── Incoming dispatch ──────────────────────────────────────────────────────

(test gmcp-incoming-dispatch-to-package-handler
  "An incoming GMCP subnegotiation is routed to the package handler."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (let* ((protocol (telnet::telnet-conn-protocol conn))
                (received nil))
           (telnet:telnet-register-gmcp-handler
            protocol "Char"
            (lambda (p message data)
              (declare (ignore p))
              (setf received (list message data))))
           ;; IAC SB GMCP "Char.Vitals {\"hp\":7}" IAC SE
           (write-bytes write-stream
                        (concatenate '(vector (unsigned-byte 8))
                                     #(255 250 201)
                                     (flexi-streams:string-to-octets
                                      "Char.Vitals {\"hp\":7}"
                                      :external-format :utf-8)
                                     #(255 240)))
           (sleep 0.1)
           (telnet:telnet-read-char conn :timeout 2)
           (is (equal received '("Vitals" "{\"hp\":7}"))
               "Handler should receive the message and payload"))
      (close-test-connection conn write-stream))))

(test gmcp-incoming-ignores-unregistered-package
  "An incoming GMCP message with no registered package handler is ignored."
  (multiple-value-bind (conn write-stream) (make-test-telnet-connection)
    (unwind-protect
         (progn
           (write-bytes write-stream
                        (concatenate '(vector (unsigned-byte 8))
                                     #(255 250 201)
                                     (flexi-streams:string-to-octets
                                      "Other.Thing" :external-format :utf-8)
                                     #(255 240)))
           (sleep 0.1)
           ;; Should not signal; just consume the subnegotiation.
           (multiple-value-bind (char status)
               (telnet:telnet-read-char conn :timeout 2)
             (is (null char))
             (is (eq status :timeout))))
      (close-test-connection conn write-stream))))