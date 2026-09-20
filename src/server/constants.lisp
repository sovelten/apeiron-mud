;;;; src/server/constants.lisp — Server-specific configuration
;;;;
;;;; Shared game constants (object types, *debug-mode*, etc.) are in
;;;; src/core/constants.lisp and inherited via the apeiron.core package.

(in-package #:apeiron.server)

;; Server configuration
;;
;; NOTE: these are DEFVAR, not DEFPARAMETER, on purpose.  A running server
;; is expected to be hot-reloaded in place (see RELOAD-APEIRON /
;; SAFE-UPDATE, which call (QL:QUICKLOAD :APEIRON)).  When ASDF reloads
;; this file, DEFPARAMETER would re-evaluate the defaults and clobber the
;; live configuration — resetting *SERVER-SSL-CERTIFICATE* and
;; *SERVER-SSL-KEY* to NIL while the TLS listener keeps running, which
;; makes every subsequent handshake fail with OpenSSL's opaque
;; "no shared cipher" (no certificate to select a cipher for).  DEFVAR
;; leaves an already-bound variable untouched, so runtime configuration
;; survives a reload.
(defvar *server-host* "0.0.0.0")
(defvar *server-port* 8888)
(defvar *max-connections* 100)
(defvar *buffer-size* 4096)

;; TLS configuration
(defvar *server-tls-port* 8889
  "Port for TLS-encrypted telnet connections.  The IANA-registered port
for telnet-over-TLS is 992, but ports below 1024 require root
privileges.  8889 is the default for development and matches the
common MUD + 1 pattern (plain-text 8888 → TLS 8889).")

(defvar *server-ssl-certificate* nil
  "Path to the PEM-encoded SSL/TLS certificate file.
Set to a path string (e.g. \"/etc/ssl/certs/mud-server.pem\") to enable TLS.
When nil, the TLS listener will not start.")

(defvar *server-ssl-key* nil
  "Path to the PEM-encoded SSL/TLS private key file.
Set to a path string (e.g. \"/etc/ssl/private/mud-server.key\") to enable TLS.")

(defvar *server-ssl-password* nil
  "Password for the SSL private key, if encrypted.")

(defvar *server-tls-prefer-start-tls* nil
  "When true, offer the START_TLS telnet option (option 46) on the
plain-text port, allowing clients to upgrade to TLS in-band.

Default is NIL because START_TLS has very limited client support in
practice (TinTin++ does not implement it, Mudlet has partial support).
The dedicated TLS port (controlled by *SERVER-TLS-PORT*) is the
reliable way to provide encrypted connections.  Set this to T only
if you know your client supports option 46.")

(defvar *mud-name* "Apeiron MUD"
  "The name of this MUD server, used in MSSP responses and other
protocol-level identification contexts.")
