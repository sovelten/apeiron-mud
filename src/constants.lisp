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
(defparameter *server-tls-port* 992
  "Port for TLS-encrypted telnet connections (IANA-registered for
telnet-over-TLS, also commonly used by MUDs for SSL/TLS).")

(defparameter *server-ssl-certificate* nil
  "Path to the PEM-encoded SSL/TLS certificate file.
Set to a path string (e.g. \"/etc/ssl/certs/mud-server.pem\") to enable TLS.
When nil, the TLS listener will not start.")

(defparameter *server-ssl-key* nil
  "Path to the PEM-encoded SSL/TLS private key file.
Set to a path string (e.g. \"/etc/ssl/private/mud-server.key\") to enable TLS.")

(defparameter *server-ssl-password* nil
  "Password for the SSL private key, if encrypted.")

(defparameter *server-tls-prefer-start-tls* t
  "When true, also offer the START_TLS telnet option (option 46) on the
plain-text port, allowing clients to upgrade the connection in place.
When nil, TLS is only available via the dedicated TLS port.")
