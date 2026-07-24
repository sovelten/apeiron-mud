;;;; src/server/session-telnet.lisp — Telnet-backed session implementation
;;;;
;;;; Bridges the telnet subsystem (apeiron-telnet) and the MUD core
;;;; (apeiron-core) by implementing the core session protocol using
;;;; telnet:telnet-connection for RFC 854 compliant I/O.
;;;;
;;;; This file belongs in the server module because it depends on both
;;;; the telnet package and the core mud package, wiring the two together.

(in-package :apeiron.server)

;;
;; Implementation of mud-session using the telnet server module
;; (attempts to respect RFC 854)
;;

(defclass telnet-session (mud-session)
  ((telnet-conn :initarg :telnet-conn
                :reader session-telnet-connection
                :documentation "The telnet:telnet-connection backing this session.")
   (mssp-info-fn :initarg :mssp-info-fn
                 :initform nil
                 :reader session-mssp-info-fn
                 :documentation "A function of no arguments returning an alist of
(variable-name-string . value-string) conses for MSSP responses, or NIL to
disable MSSP support on this session."))
  (:documentation "A session backed by a telnet:telnet-connection.

This session implements RFC 854-compliant telnet I/O with proper
IAC command processing, option negotiation, and keepalive via NOP.
The telnet subsystem is fully decoupled from MUD game logic."))

(defmethod session-stream ((session telnet-session))
  "Telnet sessions do not expose a raw CL stream.
Use telnet:telnet-read-line / telnet:telnet-write-string instead."
  nil)

(defmethod session-keepalive ((session telnet-session))
  "Send a Telnet NOP (RFC 854) to keep the connection alive."
  (telnet:telnet-send-nop (session-telnet-connection session)))

(defmethod mud-read-line ((session telnet-session) &key (timeout 300))
  "Read a line from the telnet session using RFC 854-compliant I/O."
  (let ((conn (session-telnet-connection session)))
    (if conn
        (handler-case
            (telnet:telnet-read-line conn :timeout timeout :poll-interval 0.1)
          (telnet:telnet-connection-lost (e)
            (declare (ignore e))
            (values nil :connection-lost))
          (telnet:telnet-error (e)
            (log-error "Telnet read error: ~A" (telnet:telnet-error-message e))
            (values nil :eof)))
        (values nil :eof))))

(defmethod mud-write ((session telnet-session) message &key (newline t))
  "Write a message to the telnet session using RFC 854-compliant I/O."
  (let ((conn (session-telnet-connection session)))
    (when conn
      (handler-case
          (telnet:telnet-write-string conn message
                                      :end (if newline :crlf nil))
        (telnet:telnet-connection-lost (e)
          (declare (ignore e))
          nil)
        (telnet:telnet-error (e)
          (log-error "Telnet write error: ~A" (telnet:telnet-error-message e))
          nil)))))

(defmethod session-disconnect ((session telnet-session))
  "Disconnect the telnet session — close the telnet connection,
then clear the character link via CALL-NEXT-METHOD."
  (let ((conn (session-telnet-connection session)))
    (when conn
      (handler-case
          (telnet:telnet-connection-close conn)
        (error (e)
          (log-error "Error closing telnet connection: ~A" e)))))
  (call-next-method))

(defmethod session-send-prompt ((session telnet-session))
  "Send a prompt followed by the End-of-Record (EOR) signal.
Writes > to the client and then sends IAC SB EOR IAC SE (RFC 885)
so that MUD clients can reliably detect prompt
boundaries for trigger matching, GMCP framing, and similar features.
The EOR is only sent if it was successfully negotiated (the client
responded DO EOR). If the connection is lost, errors are silently
ignored."
  (let ((conn (session-telnet-connection session)))
    (when conn
      (handler-case
          (progn
            (telnet::telnet-write-string conn "> " :end nil)
            (telnet::telnet-send-eor conn))
        (telnet::telnet-connection-lost (e)
          (declare (ignore e))
          nil)
        (telnet::telnet-error (e)
          (log-error "Telnet prompt error: ~A" (telnet::telnet-error-message e))
          nil)))))

;; ─── Telnet session constructors ────────────────────────────────────────────

;; ─── MSSP support ───────────────────────────────────────────────────────────

(defun %setup-telnet-mssp (protocol mssp-info-fn)
  "Register MSSP (MUD Server Status Protocol) support on PROTOCOL.

MSSP-INFO-FN is a function of no arguments.  It should return a list of
(variable-name-string . value-string) conses describing the server state.

This function:
1. Marks the MSSP telnet option (70) as wanted locally, so the server
   responds WILL to any DO MSSP the client sends.
2. Registers a subnegotiation handler that responds to MSSP-VAR
   \"REQUEST\" by calling MSSP-INFO-FN and sending the result back
   as an MSSP response: IAC SB MSSP (MSSP-VAR N MSSP-VAL V)* IAC SE."
  ;; Mark the MSSP option as wanted locally
  (let ((state (telnet::ensure-option-state protocol :local +telnet-opt-mssp+)))
    (setf (telnet::telnet-option-state-wanted state) t
          (telnet::telnet-option-state-pending state) t))
  (log-message "[MSSP] MSSP option marked as wanted on protocol ~A" (sb-kernel:get-lisp-obj-address protocol))
  ;; Register the subnegotiation handler
  (telnet-register-option-handler
   protocol +telnet-opt-mssp+
   (lambda (protocol option data)
     (declare (ignore option))
     (log-message "[MSSP] Handler called! data length=~D option=~D"
                  (length data) option)
     (when (>= (length data) 1)
       (log-message "[MSSP] data[0]=~D (+mssp-var+=~D)"
                    (aref data 0) +mssp-var+))
     ;; An MSSP request is: MSSP-VAR \"REQUEST\"
     (when (and (>= (length data) 8)
                (= (aref data 0) +mssp-var+))
       (let ((request (map 'string #'code-char (subseq data 1 8))))
         (log-message "[MSSP] request string=~S" request)
         (when (string= request "REQUEST")
           (log-message "[MSSP] MATCH! Calling mssp-info-fn")
           (let ((vars (funcall mssp-info-fn)))
             (log-message "[MSSP] mssp-info-fn returned ~D vars" (length vars))
             (when vars
               (let ((parts (make-array 64 :element-type '(unsigned-byte 8)
                                           :adjustable t :fill-pointer 0)))
                 (dolist (pair vars)
                   (vector-push-extend +mssp-var+ parts)
                   (loop for c across (car pair)
                         do (vector-push-extend (char-code c) parts))
                   (vector-push-extend +mssp-val+ parts)
                   (loop for c across (cdr pair)
                         do (vector-push-extend (char-code c) parts)))
                 (let ((response (telnet::make-subneg-command +telnet-opt-mssp+ parts)))
                   (log-message "[MSSP] Sending response (~D bytes)" (length response))
                   (list response)))))))))))

(defun %drain-telnet-negotiation (conn)
  "Process all pending telnet negotiation commands (IAC WILL/WONT/DO/DONT
and subnegotiations) from the connection, before the login flow starts.

Data characters are buffered and re-inserted into the line buffer so
they can be read normally during the login flow.  This ensures that
protocol-level exchanges like MSSP are handled immediately — before
the server writes the login prompt and begins reading input — rather
than lazily during the first read call.

Must be called after %SETUP-TELNET-MSSP so that the MSSP handler is
already registered.

Waits up to DRAIN-TIMEOUT seconds for initial data to arrive (the
grapevine MSSP checker typically responds within a few hundred ms of
receiving the initial server negotiation)."
  (let* ((chars (make-array 64 :element-type 'character
                              :adjustable t :fill-pointer 0))
         (drain-timeout 1.5)
         (deadline (+ (get-internal-real-time)
                      (* drain-timeout internal-time-units-per-second))))
    (loop
      (let ((remaining (- deadline (get-internal-real-time))))
        (when (<= remaining 0) (return))
        (multiple-value-bind (char status)
            (telnet:telnet-read-char conn
                                     :timeout (max 0.01
                                                   (/ remaining
                                                      internal-time-units-per-second)))
          (cond
            ((and char (null status))
             (vector-push-extend char chars))
            ((eq status :eof)
             (return))
            ((eq status :connection-lost)
             (return))
            ;; :timeout — loop back and check deadline
            (t nil)))))
    ;; Re-insert saved characters into the line buffer in original order
    (when (> (fill-pointer chars) 0)
      (let ((line (slot-value conn 'telnet::line-buffer)))
        (loop for i from 0 below (fill-pointer chars)
              do (vector-push-extend (aref chars i) line))
        (log-message "[MSSP] Drain: re-inserted ~D chars into line buffer"
                     (fill-pointer chars))))))

(defun %make-telnet-session (conn &key mssp-info-fn)
  "Create a telnet-session from an already-validated telnet-connection.
When MSSP-INFO-FN is provided, enables MSSP support on the session."
  (when mssp-info-fn
    (%setup-telnet-mssp (telnet:telnet-conn-protocol conn) mssp-info-fn))
  (make-instance 'telnet-session
                 :id (make-id)
                 :telnet-conn conn
                 :mssp-info-fn mssp-info-fn))

(defun new-telnet-session (usocket &key start-tls certificate key password
                                           mssp-info-fn)
  "Create a new telnet-session from an accepted usocket.
Performs initial RFC 854 telnet option negotiation and returns
a session ready for I/O.

When START-TLS is true, the START_TLS telnet option (46) is offered
during initial negotiation.  If the client responds DO START_TLS, the
connection is automatically upgraded to TLS in-band.  CERTIFICATE,
KEY, and PASSWORD are required when START-TLS is true.

MSSP-INFO-FN, when provided, enables MSSP (MUD Server Status Protocol,
telnet option 70) support.  It is a function of no arguments that
returns a list of (variable-name-string . value-string) conses describing
the server state (e.g. NAME, PLAYERS, UPTIME).

Returns NIL if the connection is rejected as non-telnet traffic
(e.g., HTTP requests or TLS ClientHello on the plain-text port)."
  (let* ((protocol (if start-tls
                       (telnet-register-start-tls
                        (make-instance 'telnet-protocol))
                       (make-instance 'telnet-protocol)))
         (conn (telnet:make-telnet-connection usocket :protocol protocol)))
    ;; Validate that the client is actually speaking telnet, not HTTP/TLS/etc.
    (unless (telnet-validate-connection conn :timeout 1.5)
      (log-message "Rejected non-telnet connection on plain-text port")
      (usocket:socket-close usocket)
      (return-from new-telnet-session nil))
    ;; Install START_TLS upgrade callback if requested
    (when start-tls
      (setf (telnet:telnet-conn-tls-upgrade-fn conn)
            (let ((cert certificate)
                  (key key)
                  (pwd password))
              (lambda ()
                (handler-case
                    (progn
                      (telnet:telnet-start-tls conn
                                               :certificate cert
                                               :key key
                                               :password pwd)
                      (log-message
                       "Connection upgraded to TLS via START_TLS"))
                  (telnet:telnet-tls-error (e)
                    (log-error
                     "START_TLS upgrade failed: ~A"
                     (telnet:telnet-error-message e))))))))
      (log-message "[MSSP] new-telnet-session: mssp-info-fn is ~:[nil~;provided~]"
                 mssp-info-fn)
    (let ((session (%make-telnet-session conn :mssp-info-fn mssp-info-fn)))
      ;; Drain and process any pending telnet negotiation (including MSSP)
      ;; BEFORE the session enters the login flow.  This ensures the MSSP
      ;; response is sent immediately, not lazily during the first read call
      ;; in ask-input which happens after "What is your name?" is already sent.
      (%drain-telnet-negotiation conn)
      session)))

(defun new-telnet-tls-session (usocket &key certificate key password mssp-info-fn)
  "Create a new telnet-session with immediate TLS encryption from an
accepted usocket.  Performs the TLS handshake (SSL_accept) and then
initial RFC 854 telnet option negotiation.

CERTIFICATE and KEY are paths to PEM-encoded certificate and private
key files.  PASSWORD is the optional decryption password for the key.

MSSP-INFO-FN, when provided, enables MSSP (MUD Server Status Protocol,
telnet option 70) support.  It is a function of no arguments that
returns a list of (variable-name-string . value-string) conses describing
the server state (e.g. NAME, PLAYERS, UPTIME).

Returns NIL if the connection is rejected as non-telnet traffic
(e.g., HTTP-over-TLS on the secure port)."
  (let ((conn (telnet:make-telnet-tls-connection usocket
                                                  :certificate certificate
                                                  :key key
                                                  :password password)))
    ;; Validate that the TLS client is actually speaking telnet, not HTTP/etc.
    (unless (telnet-validate-connection conn :timeout 1.5)
      (log-message "Rejected non-telnet TLS connection on secure port")
      (usocket:socket-close usocket)
      (return-from new-telnet-tls-session nil))
    (log-message "[MSSP] new-telnet-session: mssp-info-fn is ~:[nil~;provided~]"
                 mssp-info-fn)
    (let ((session (%make-telnet-session conn :mssp-info-fn mssp-info-fn)))
      (%drain-telnet-negotiation conn)
      session)))

(defun new-telnet-session-with-start-tls (usocket &key certificate key password
                                                        mssp-info-fn)
  "Create a telnet-session that offers the START_TLS telnet option (46).
The initial connection is plain-text.  If the client negotiates START_TLS,
the connection is upgraded to TLS in-band using the provided credentials.

MSSP-INFO-FN, when provided, enables MSSP (MUD Server Status Protocol,
telnet option 70) support.  It is a function of no arguments that
returns a list of (variable-name-string . value-string) conses describing
the server state (e.g. NAME, PLAYERS, UPTIME).

This is a convenience wrapper around NEW-TELNET-SESSION with :START-TLS T."
  (new-telnet-session usocket
                      :start-tls t
                      :certificate certificate
                      :key key
                      :password password
                      :mssp-info-fn mssp-info-fn))
