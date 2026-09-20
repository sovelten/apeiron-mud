;;;; telnet/gmcp.lisp — Generic Mud Communication Protocol (GMCP)
;;;;
;;;; GMCP is a telnet subnegotiation protocol (option 201) that lets a
;;;; server and client exchange structured, out-of-band data (character
;;;; vitals, room contents, client capabilities, ...) alongside the
;;;; normal text stream.
;;;;
;;;; Wire format:
;;;;
;;;;   IAC WILL GMCP              (server offers the option)
;;;;   IAC DO GMCP                (client agrees)
;;;;   IAC SB GMCP <header> [ <data> ] IAC SE
;;;;
;;;; where <header> is "Package.Message" (e.g. "Char.Vitals") and the
;;;; optional <data> — separated from the header by a single space — is
;;;; conventionally a JSON document.  Neither the framing nor the payload
;;;; format is interpreted here beyond splitting header/data: GMCP is a
;;;; transport for opaque messages, and package payloads are handled by
;;;; application-registered callbacks.
;;;;
;;;; Decoupling:
;;;;   This file MUST NOT reference any application (apeiron) symbol.
;;;;   It knows only about telnet bytes and package names.  Applications
;;;;   plug into it through three hooks:
;;;;
;;;;     - TELNET-REGISTER-GMCP          negotiate the option
;;;;     - TELNET-REGISTER-GMCP-HANDLER  receive messages for a package
;;;;     - TELNET-GMCP-ON-ENABLE-FN      send initial state once enabled
;;;;
;;;;   The bridge that maps game concepts (characters, stats) onto GMCP
;;;;   packages lives outside this module (see apeiron.server's
;;;;   session-telnet.lisp).
;;;;
;;;; References:
;;;;   GMCP — https://tintin.mudhalla.net/protocols/gmcp/
;;;;   Core.Hello, Core.Supports.Set, Char.Vitals, Char.Stats packages

(in-package #:telnet)

;;; ----------------------------------------------------------------
;;; Encoding / decoding
;;; ----------------------------------------------------------------

(defun %gmcp-string-to-octets (string)
  "UTF-8 encode STRING to a (simple-array (unsigned-byte 8) (*))."
  (flexi-streams:string-to-octets string :external-format :utf-8))

(defun %gmcp-octets-to-string (octets)
  "UTF-8 decode OCTETS to a string, degrading to Latin-1 if the payload
is not valid UTF-8 (so no byte is ever lost)."
  (handler-case
      (flexi-streams:octets-to-string octets :external-format :utf-8)
    (error ()
      (map 'string #'code-char octets))))

(defun gmcp-encode (package message &optional data)
  "Return the telnet byte vector for a GMCP message.

PACKAGE and MESSAGE are strings (e.g. \"Char\" and \"Vitals\"); together
they form the message header \"Package.Message\".  DATA, when non-NIL and
non-empty, is an opaque payload string (conventionally JSON) appended after
a single space.

The result is a complete subnegotiation command:
  IAC SB GMCP <header> [ <data> ] IAC SE"
  (let* ((header (concatenate 'string package "." message))
         (text (if (and data (plusp (length data)))
                   (concatenate 'string header " " data)
                   header)))
    (make-subneg-command +telnet-opt-gmcp+
                         (%gmcp-string-to-octets text))))

(defun gmcp-decode (data)
  "Parse a GMCP subnegotiation payload DATA (a byte vector).

Returns (values PACKAGE MESSAGE DATA-STRING).  DATA-STRING is NIL when the
message carries no payload.  The header is split at the first dot; if the
header has no dot, the whole thing is treated as the package and MESSAGE is
the empty string."
  (let* ((text (%gmcp-octets-to-string data))
         (space (position #\Space text))
         (header (if space (subseq text 0 space) text))
         (payload (if space (subseq text (1+ space)) nil))
         (dot (position #\. header)))
    (if dot
        (values (subseq header 0 dot) (subseq header (1+ dot)) payload)
        (values header "" payload))))

;;; ----------------------------------------------------------------
;;; Incoming message dispatch
;;; ----------------------------------------------------------------

(defun %handle-gmcp (protocol option data)
  "Subnegotiation handler for GMCP (option 201): parse DATA and dispatch to
the handler registered for its package, if any."
  (declare (ignore option))
  (multiple-value-bind (package message payload) (gmcp-decode data)
    (let ((handler (gethash (string-downcase package)
                            (telnet-gmcp-handlers protocol))))
      (when handler
        (funcall handler protocol message payload))))
  nil)

(defun telnet-register-gmcp-handler (protocol package handler-fn)
  "Register HANDLER-FN to handle incoming GMCP messages in PACKAGE.

PACKAGE is a string (case-insensitive), e.g. \"Core\" or \"Char\".
HANDLER-FN is called as (protocol message data-string) for every incoming
GMCP message whose package matches — MESSAGE is the part after the dot
(e.g. \"Vitals\") and DATA-STRING is the payload (or NIL).  Returns
PROTOCOL."
  (setf (gethash (string-downcase package) (telnet-gmcp-handlers protocol))
        handler-fn)
  ;; Ensure the GMCP subnegotiation dispatcher is installed.  Registering
  ;; it here (rather than from INITIALIZE-INSTANCE) keeps this file free of
  ;; an :after method that would replace the one in protocol.lisp, and means
  ;; the dispatcher only exists once a handler actually needs it.
  (telnet-register-option-handler protocol +telnet-opt-gmcp+ #'%handle-gmcp)
  protocol)

;;; ----------------------------------------------------------------
;;; Negotiation
;;; ----------------------------------------------------------------

(defun telnet-register-gmcp (protocol)
  "Mark GMCP (option 201) as wanted on PROTOCOL so that an initial
WILL GMCP is included in TELNET-INIT-NEGOTIATION.

Returns PROTOCOL for chaining convenience."
  (let ((state (ensure-option-state protocol :local +telnet-opt-gmcp+)))
    (setf (telnet-option-state-wanted state) t
          (telnet-option-state-pending state) t))
  protocol)

(defun telnet-gmcp-enabled-p (connection)
  "Return T when GMCP has been successfully negotiated on CONNECTION —
that is, we offered WILL GMCP and the client answered DO GMCP.  NIL when
CONNECTION is missing/dead or the option is not enabled."
  (let ((protocol (and connection (telnet-conn-protocol connection))))
    (and protocol
         (let ((state (telnet-local-option protocol +telnet-opt-gmcp+)))
           (and state (telnet-option-state-enabled state))))))

(defun telnet-gmcp-startup-messages (protocol)
  "Return the list of encoded GMCP byte vectors to send immediately after
GMCP is enabled: the mandatory Core.Hello handshake followed, in order, by
whatever the application's TELNET-GMCP-ON-ENABLE-FN callback returns.

The callback is a function of the protocol returning a list of
(package message data) triples."
  (let ((messages
          (list (gmcp-encode "Core" "Hello"
                             (format nil "{\"client\":\"~A\",\"version\":\"~A\"}"
                                     (telnet-gmcp-client-name protocol)
                                     (telnet-gmcp-client-version protocol))))))
    (let ((fn (telnet-gmcp-on-enable-fn protocol)))
      (when fn
        (dolist (spec (funcall fn protocol))
          (destructuring-bind (package message &optional data) spec
            (setf messages
                  (append messages (list (gmcp-encode package message data))))))))
    messages))

(defmethod telnet-process-command :around
    ((p telnet-protocol) (command (eql telnet::do)) (option (eql 201)))
  "On DO GMCP: let the base handler enable the option (and answer WILL),
then append the GMCP Core.Hello handshake plus the application's on-enable
messages.  Only fires on the transition into the enabled state, so a
duplicate DO GMCP does not re-send the handshake."
  (let ((base (call-next-method)))
    (let ((state (telnet-local-option p +telnet-opt-gmcp+)))
      (when (and base state (telnet-option-state-enabled state))
        (setf base (nconc base (telnet-gmcp-startup-messages p)))))
    base))

;;; ----------------------------------------------------------------
;;; Outgoing messages
;;; ----------------------------------------------------------------

(defun telnet-send-gmcp (connection package message &optional data)
  "Send a GMCP message on CONNECTION.

PACKAGE and MESSAGE name the message (e.g. \"Char\" \"Vitals\"); DATA is an
optional opaque payload string (conventionally JSON).

Sending is a no-op — returns NIL — unless GMCP has been negotiated and the
connection is still alive, so callers may send unconditionally without
checking client capability.  Returns T when the message was written, NIL
otherwise (not negotiated, dead connection, or transport error)."
  (unless (and connection (telnet-connection-alive-p connection))
    (return-from telnet-send-gmcp nil))
  (unless (telnet-gmcp-enabled-p connection)
    (return-from telnet-send-gmcp nil))
  (handler-case
      (progn
        (telnet-write-raw connection (gmcp-encode package message data))
        t)
    (telnet-connection-lost () nil)
    (telnet-error () nil)))