;;;; telnet/tls.lisp — TLS support for telnet connections
;;;;
;;;; Implements two complementary TLS mechanisms specified by the MUD
;;;; community standards and the IETF telnet START_TLS draft:
;;;;
;;;;   1. Direct TLS (dedicated TLS port, commonly port 992 / 443)
;;;;      — the client connects and the server immediately performs a
;;;;        TLS handshake before any telnet negotiation.
;;;;
;;;;   2. START_TLS telnet option (option 46)
;;;;      — the client connects on the plain-text port, negotiates the
;;;;        START_TLS telnet option via standard WILL/DO, and then the
;;;;        connection is upgraded to TLS in-band.
;;;;
;;;; References:
;;;;   Telnet START_TLS IETF draft
;;;;   MUD TLS community best practice (Mudlet, TinTin++, MUSHclient)
;;;;
;;;; Dependencies: cl+ssl (OpenSSL bindings)

(in-package #:telnet)

;;; ----------------------------------------------------------------
;;; Telnet START_TLS Option
;;; ----------------------------------------------------------------
;;;
;;; Option 46 — START_TLS.  Per the IETF draft, the server offers WILL
;;; START_TLS during initial negotiation.  If the client responds with
;;; DO START_TLS, the TLS handshake begins immediately (no further
;;; telnet negotiation for this option).

;; +TELNET-OPT-START-TLS+ is defined as defconstant in protocol.lisp.

;;; ----------------------------------------------------------------
;;; TLS-specific condition
;;; ----------------------------------------------------------------

(define-condition telnet-tls-error (telnet-error)
  ()
  (:report (lambda (c s)
             (format s "Telnet TLS error: ~A" (telnet-error-message c))))
  (:documentation "Raised on TLS-related errors (handshake failure,
certificate issues, etc.)."))

;;; ----------------------------------------------------------------
;;; TLS connection predicate
;;; ----------------------------------------------------------------

(defun telnet-tls-connection-p (conn)
  "Return T when CONN has an active TLS session — i.e. its raw stream
is an SSL stream returned by cl+ssl."
  (ignore-errors
    (let* ((pkg (find-package :cl+ssl))
           (class-name (and pkg (find-symbol "SSL-SERVER-STREAM" pkg)))
           (class (and class-name (find-class class-name nil))))
      (and class (typep (telnet-conn-raw-stream conn) class)))))

;;; ----------------------------------------------------------------
;;; Internal: create a bidirectional binary stream on a socket FD
;;; ----------------------------------------------------------------

(defun %make-binary-bidi-stream (fd)
  "Create a bidirectional binary (unsigned-byte 8) stream on FD.
Unlike the dup-based approach in connection.lisp (which creates
separate input and output streams for full-duplex line discipline),
this creates a single stream for both directions — required by the
SSL BIO layer in cl+ssl, which needs a single transport for the
bidirectional TLS record layer.

WAIT: fd-stream buffers are not used here — SSL has its own buffering."
  #+sbcl
  (sb-sys:make-fd-stream fd
                          :input t :output t
                          :element-type '(unsigned-byte 8)
                          :buffering :full
                          :name "telnet-tls-bidi-stream")
  #+ccl
  (ccl:make-fd-stream fd :direction :io
                       :element-type '(unsigned-byte 8))
  #+ecl
  (ext:make-stream-from-fd fd :direction :io
                           :element-type '(unsigned-byte 8))
  #-(or sbcl ccl ecl)
  (error "telnet tls: unsupported Lisp implementation for TLS."))

;;; ----------------------------------------------------------------
;;; Direct TLS — dedicated TLS port
;;; ----------------------------------------------------------------

(defun make-telnet-tls-connection (usocket &key certificate key password)
  "Create a new telnet-connection that is immediately encrypted with TLS.

USOCKET is a freshly-accepted usocket:stream-usocket from a TLS listener.
CERTIFICATE and KEY are paths to PEM-encoded certificate and private key
files.  PASSWORD is the (optional) password for the private key.

The server-side TLS handshake (OpenSSL SSL_accept) is performed during
this call.  On success, the returned telnet-connection is ready for use
with all standard telnet I/O functions; all traffic is encrypted.

On handshake failure, a telnet-tls-error is signalled."
  (let* ((fd (%socket-fd usocket))
         (plain-stream (%make-binary-bidi-stream fd))
         (ssl-stream
           (handler-case
               (cl+ssl:make-ssl-server-stream
                plain-stream
                :certificate certificate
                :key key
                :password password
                :close-callback (lambda (s)
                                  (declare (ignore s))
                                  (ignore-errors (close plain-stream))))
             (error (e)
               (ignore-errors (close plain-stream))
               (error 'telnet-tls-error
                      :message (format nil "TLS handshake failed: ~A" e))))))
    (let* ((protocol (make-instance 'telnet-protocol))
           (conn (make-instance 'telnet-connection
                                :usocket usocket
                                :raw-stream ssl-stream
                                :protocol protocol)))
      ;; Send initial telnet option negotiation (now encrypted)
      (let ((init-cmds (telnet-init-negotiation protocol)))
        (dolist (cmd init-cmds)
          (handler-case
              (write-sequence cmd (telnet-conn-out-stream conn))
            (stream-error (e)
              (declare (ignore e))
              (setf (telnet-connection-alive-p conn) nil)
              (return-from make-telnet-tls-connection conn))))
        (force-output (telnet-conn-out-stream conn)))
      conn)))

;;; ----------------------------------------------------------------
;;; START_TLS — in-band upgrade
;;; ----------------------------------------------------------------

(defun telnet-start-tls (conn &key certificate key password)
  "Upgrade an existing plain telnet-connection to TLS.

The server-side TLS handshake (OpenSSL SSL_accept) is performed during
this call.  The connection's existing protocol state (negotiated telnet
options, NAWS window size, terminal type, etc.) is preserved.

After this call returns successfully, all further I/O on CONN is
encrypted.  Signals telnet-tls-error on failure.

This is an in-place upgrade: the same telnet-connection object is used;
only the underlying byte streams are replaced with SSL-wrapped streams."
  (let* ((usocket (telnet-conn-usocket conn))
         (fd (when usocket (%socket-fd usocket))))
    (unless fd
      (error 'telnet-tls-error
             :message "Cannot upgrade to TLS: no socket FD available."))
    (let* ((plain-stream (%make-binary-bidi-stream (sb-posix:dup fd)))
           (ssl-stream
             (handler-case
                 (cl+ssl:make-ssl-server-stream
                  plain-stream
                  :certificate certificate
                  :key key
                  :password password
                  :close-callback (lambda (s)
                                    (declare (ignore s))
                                    (ignore-errors (close plain-stream))))
               (error (e)
                 (ignore-errors (close plain-stream))
                 (error 'telnet-tls-error
                        :message
                        (format nil "TLS handshake during START_TLS failed: ~A"
                                e))))))
      ;; Close the old binary streams (the dup'd FDs)
      (handler-case
          (close (telnet-conn-raw-stream conn))
        (error () nil))
      (let ((old-out (telnet-conn-out-stream-slot conn)))
        (when (and old-out (not (eq old-out (telnet-conn-raw-stream conn))))
          (handler-case (close old-out) (error () nil))))
      ;; Replace with the new SSL-wrapped stream (bidirectional)
      (setf (slot-value conn 'raw-stream) ssl-stream
            (slot-value conn 'out-stream) nil)
      conn)))

;;; ----------------------------------------------------------------
;;; START_TLS option negotiation handler
;;; ----------------------------------------------------------------
;;;
;;; The generic telnet-process-command for DO wants to respond with WILL
;;; (confirming the option).  For START_TLS, however, once the client
;;; accepts our WILL START_TLS offer by sending DO START_TLS, we must
;;; NOT send a telnet response — the TLS handshake begins immediately.
;;;
;;; We use an :around method that shadows the generic DO handler for
;;; option 46, returning NIL so no response bytes are written.
;;; The actual TLS upgrade is triggered via the connection's
;;; tls-upgrade-fn callback (if set), called from %handle-telnet-command.

(defmethod telnet-process-command :around
    ((p telnet-protocol) (command (eql telnet::do)) (option (eql 46)))
  "Override DO START_TLS handling: never send WILL back, the TLS
handshake replaces telnet negotiation at this point."
  (let ((state (ensure-option-state p :local option)))
    (cond
      ((telnet-option-state-enabled state)
       nil)
      ((telnet-option-state-wanted state)
       (setf (telnet-option-state-enabled state) t
             (telnet-option-state-pending state) nil)
       nil)                           ; no response — start TLS instead
      (t
       (list (make-command-2 telnet::wont option))))))

;;; ----------------------------------------------------------------
;;; Convenience: add START_TLS offer to a protocol's negotiation
;;; ----------------------------------------------------------------

(defun telnet-register-start-tls (protocol)
  "Register the START_TLS option on PROTOCOL so that an initial
WILL START_TLS is sent during option negotiation.

Returns PROTOCOL for chaining convenience:

  (let ((protocol (telnet-register-start-tls
                    (make-instance 'telnet-protocol))))
    ...)"
  (let ((state (ensure-option-state protocol :local +telnet-opt-start-tls+)))
    (setf (telnet-option-state-wanted state) t
          (telnet-option-state-pending state) t))
  protocol)
