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
(defconstant +object-type-player+ 'player)
(defconstant +object-type-item+ 'item)

;; Command constants
(defconstant +max-command-length+ 256)
(defconstant +command-timeout+ 30)
