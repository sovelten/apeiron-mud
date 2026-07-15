;;;; telnet/package.lisp — Package definition for the standalone Telnet subsystem
;;;;
;;;; This package is maximally decoupled from the rest of the MUD software.
;;;; It depends only on usocket, flexi-streams, and bordeaux-threads for
;;;; portable socket/stream/thread abstractions.

(defpackage #:telnet
  (:use #:cl)
  ;; Shadow CL symbols that conflict with RFC 854 command names
  (:shadow #:do #:dont #:will #:wont #:break #:sb)
  (:export
   ;; Condition types
   #:telnet-error
   #:telnet-error-message
   #:telnet-connection-lost
   #:telnet-tls-error

   ;; Protocol engine
   #:telnet-protocol
   #:telnet-init-negotiation
   #:telnet-process-command
   #:telnet-process-subnegotiation
   #:telnet-in-subneg-p

   ;; Protocol state accessors
   #:telnet-window-width
   #:telnet-window-height
   #:telnet-terminal-type

   ;; Connection lifecycle
   #:telnet-connection
   #:make-telnet-connection
   #:telnet-validate-connection
   #:telnet-connection-alive-p
   #:telnet-connection-close

   ;; I/O API
   #:telnet-read-line
   #:telnet-read-char
   #:telnet-write-string
   #:telnet-send-nop
   #:telnet-send-eor
   #:telnet-write-raw

   ;; Stream access (for application layer)
   #:telnet-connection-input-stream
   #:telnet-connection-output-stream

   ;; Protocol constants (useful for diagnostics / extension)
   #:iac
   #:dont #:do #:wont #:will
   #:sb #:se
   #:eor
   #:nop #:dm #:break #:ip #:ao #:ayt #:ec #:el #:ga

   ;; Telnet options
   #:+telnet-opt-binary+
   #:+telnet-opt-echo+
   #:+telnet-opt-suppress-go-ahead+
   #:+telnet-opt-naws+
   #:+telnet-opt-terminal-type+
   #:+telnet-opt-eor+
   #:+telnet-opt-start-tls+
   ;; +telnet-opt-naws+ above is the NAWS (window size) option

   ;; Option negotiation API
   #:telnet-local-option
   #:telnet-remote-option
   #:telnet-register-option-handler

   ;; Connection internals (for TLS upgrade)
   #:telnet-conn-tls-upgrade-fn
   #:telnet-conn-protocol

   ;; TLS support
   #:telnet-tls-connection
   #:make-telnet-tls-connection
   #:telnet-start-tls
   #:telnet-tls-connection-p
   #:telnet-register-start-tls))
