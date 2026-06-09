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
   #:create-object
   #:object-id
   #:object-name
   #:object-location
   #:object-properties
   #:object-get-property
   #:object-set-property
   #:object-move
   #:object-describe
   
   ;; World system
   #:get-config-key
   #:mud-room
   #:create-room
   #:create-room!
   #:room-contents
   #:room-add-object
   #:room-remove-object
   #:room-exits
   #:room-add-exit
   #:room-add-exits
   #:room-get-exit
   #:world-restore-or-initialize
   #:world-new-character
   #:world-add-room
   #:character-by-id
   #:room-by-id
   #:rooms
   #:total-rooms
   #:*players*
   #:*system*
   
   ;; Player system
   #:mud-character
   #:mud-session
   #:create-character
   #:session-socket
   #:session-input-buffer
   #:character-session
   #:player-location
   #:player-inventory
   #:character-inventory-add
   #:character-inventory-remove
   #:player-send-message
   #:player-send-prompt
   #:remove-character
   
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
