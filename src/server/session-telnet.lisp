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
                :documentation "The telnet:telnet-connection backing this session."))
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

(defun new-telnet-session (usocket &key start-tls certificate key password)
  "Create a new telnet-session from an accepted usocket.
Performs initial RFC 854 telnet option negotiation and returns
a session ready for I/O.

When START-TLS is true, the START_TLS telnet option (46) is offered
during initial negotiation.  If the client responds DO START_TLS, the
connection is automatically upgraded to TLS in-band.  CERTIFICATE,
KEY, and PASSWORD are required when START-TLS is true.

A connection guard rejects non-telnet clients (HTTP, TLS probes,
binary garbage) before any MUD resources are allocated."
  (multiple-value-bind (ok initial-byte)
      (telnet:telnet-guard-connection usocket)
    (unless ok
      (error 'telnet:telnet-error
             :message "Connection rejected by telnet guard"))
    (let* ((protocol (if start-tls
                         (telnet:telnet-register-start-tls
                          (make-instance 'telnet:telnet-protocol))
                         (make-instance 'telnet:telnet-protocol)))
           (conn (telnet:make-telnet-connection usocket
                                                :protocol protocol
                                                :initial-byte initial-byte)))
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
      (make-instance 'telnet-session
                     :id (make-id)
                     :telnet-conn conn))))

(defun new-telnet-tls-session (usocket &key certificate key password)
  "Create a new telnet-session with immediate TLS encryption from an
accepted usocket.  Performs the TLS handshake (SSL_accept) and then
initial RFC 854 telnet option negotiation.

CERTIFICATE and KEY are paths to PEM-encoded certificate and private
key files.  PASSWORD is the optional decryption password for the key.

Returns a telnet-session ready for I/O — all traffic is encrypted."
  (make-instance 'telnet-session
                 :id (make-id)
                 :telnet-conn
                 (telnet:make-telnet-tls-connection usocket
                                                    :certificate certificate
                                                    :key key
                                                    :password password)))

(defun new-telnet-session-with-start-tls (usocket &key certificate key password)
  "Create a telnet-session that offers the START_TLS telnet option (46).
The initial connection is plain-text.  If the client negotiates START_TLS,
the connection is upgraded to TLS in-band using the provided credentials.

This is a convenience wrapper around NEW-TELNET-SESSION with :START-TLS T."
  (new-telnet-session usocket
                      :start-tls t
                      :certificate certificate
                      :key key
                      :password password))
