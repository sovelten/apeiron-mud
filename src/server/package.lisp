(defpackage #:apeiron.server
  (:use #:cl
        #:apeiron.core
        #:apeiron.core.utils
        #:apeiron.persistence
        #:telnet
        #:usocket
        #:bordeaux-threads)
  ;; Shadow the same RFC 854 command symbols that telnet shadows,
  ;; so they can be inherited from telnet without CL conflicts.
  (:shadow #:do #:dont #:will #:wont #:break #:sb)
  (:export
   ;; Server control
   #:start-mud-server
   #:stop-mud-server
   #:get-server-status
   #:*server-running*
   #:*server-socket*

   ;; Server config
   #:*server-host*
   #:*server-port*
   #:*max-connections*
   #:*buffer-size*
   #:*server-tls-port*
   #:*server-ssl-certificate*
   #:*server-ssl-key*
   #:*server-ssl-password*
   #:*server-tls-prefer-start-tls*

   ;; Telnet session constructors (bridge between telnet and core)
   #:telnet-session
   #:session-telnet-connection
   #:new-telnet-session
   #:new-telnet-tls-session
   #:new-telnet-session-with-start-tls))
