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
   #:mud-room
   #:create-room
   #:room-contents
   #:room-add-object
   #:room-remove-object
   #:room-exits
   #:room-add-exit
   #:room-add-exits
   #:room-get-exit
   #:world-initialize
   #:world-add-room
   #:world-get-room
   #:world-all-rooms
   #:*world*
   #:*players*
   #:*start-room*
   
   ;; Player system
   #:mud-player
   #:create-player
   #:player-socket
   #:player-location
   #:player-inventory
   #:player-inventory-add
   #:player-inventory-remove
   #:player-send-message
   #:player-send-prompt
   #:player-disconnect
   #:player-username
   #:player-registration-state
   
   ;; Registration system
   #:register-new-player
   #:validate-login
   #:player-exists-p
   #:get-player-display-name
   #:update-player-display-name
   #:get-all-registered-players
   #:get-player-object
   #:update-player-socket
   
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
