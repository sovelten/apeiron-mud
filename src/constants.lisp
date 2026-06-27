(in-package #:mud)

(defparameter *mud-version* "0.0.1")
(defparameter *debug-mode* t)

;; Server configuration
(defparameter *server-host* "0.0.0.0")
(defparameter *server-port* 8888)
(defparameter *max-connections* 100)
(defparameter *buffer-size* 4096)

;; Object type constants
(defconstant +object-type-generic+ 'generic)
(defconstant +object-type-room+ 'room)
(defconstant +object-type-character+ 'character)
(defconstant +object-type-item+ 'item)

;; Command constants
(defconstant +max-command-length+ 256)
(defconstant +command-timeout+ 30)

;; TLS configuration
(defparameter *server-tls-port* 8889
  "Port for TLS-encrypted telnet connections.  The IANA-registered port
for telnet-over-TLS is 992, but ports below 1024 require root
privileges.  8889 is the default for development and matches the
common MUD + 1 pattern (plain-text 8888 → TLS 8889).")

(defparameter *server-ssl-certificate* nil
  "Path to the PEM-encoded SSL/TLS certificate file.
Set to a path string (e.g. \"/etc/ssl/certs/mud-server.pem\") to enable TLS.
When nil, the TLS listener will not start.")

(defparameter *server-ssl-key* nil
  "Path to the PEM-encoded SSL/TLS private key file.
Set to a path string (e.g. \"/etc/ssl/private/mud-server.key\") to enable TLS.")

(defparameter *server-ssl-password* nil
  "Password for the SSL private key, if encrypted.")

(defparameter *server-tls-prefer-start-tls* nil
  "When true, offer the START_TLS telnet option (option 46) on the
plain-text port, allowing clients to upgrade to TLS in-band.

Default is NIL because START_TLS has very limited client support in
practice (TinTin++ does not implement it, Mudlet has partial support).
The dedicated TLS port (controlled by *SERVER-TLS-PORT*) is the
reliable way to provide encrypted connections.  Set this to T only
if you know your client supports option 46.")
