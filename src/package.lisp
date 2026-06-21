(defpackage #:mud
  (:use #:cl)
  (:export
   ;; Core exports
   #:*mud-version*
   #:*debug-mode*
   
   ;; Server control
   #:start
   #:stop
   #:status
   
   ;; Object system
   #:mud-object
   #:new-object
   #:object-id
   #:object-name
   #:object-location
   #:object-properties
   #:object-get-property
   #:object-set-property
   #:object-move
   #:object-describe
   #:mud-guestbook
   #:new-guestbook
   #:guestbook-entries
   #:guestbook-add-entry
   #:guestbook-format-entries
   
   ;; World system
   #:get-config-key
   #:mud-room
   #:new-room
   #:room-contents
   #:room-add-object
   #:room-remove-object
   #:room-exits
   #:room-add-exit
   #:room-add-exits
   #:room-get-exit
   #:new-world
   #:world-restore-or-initialize
   #:world-add-character!
   #:world-set-object-id!
   #:world-object-by-id
   #:world-object-with-name
   #:world-all-objects
   #:world-room-by-id
   #:world-rooms
   #:world-total-rooms
   #:character-by-id
   #:room-by-id
   #:rooms
   #:total-rooms
   #:starting-room
   #:sync-world
   #:*system*
   
   ;; Player / Session system
   #:mud-character
   #:mud-session
   #:new-character
   #:session-socket
   #:session-input-buffer
   #:character-session
   #:player-location
   #:player-inventory
   #:character-inventory-add
   #:character-inventory-remove
   #:player-send-message
   #:world-remove-character!
   ;; Session types
   #:stream-session
   #:telnet-session
   #:session-telnet-connection
   #:session-stream
   #:session-keepalive
   #:session-disconnect
   ;; Session constructors
   #:new-session
   #:new-telnet-session
   
   ;; Command system
   #:process-command
   
   ;; Network/Server
   #:start-mud-server
   #:stop-mud-server
   #:get-server-status
   #:*server-running*))

(defpackage #:mud.utils
  (:use #:cl)
  (:export
   #:make-id
   #:format-message
   #:log-message
   #:log-error))
