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
   #:world-new-character
   #:world-add-room
   #:world-get-player
   #:world-get-room
   #:world-all-rooms
   #:*world*
   #:*players*
   #:*start-room*
   
   ;; Player system
   #:mud-character
   #:mud-session
   #:create-character
   #:session-socket
   #:session-input-buffer
   #:player-session
   #:player-location
   #:player-inventory
   #:player-inventory-add
   #:player-inventory-remove
   #:player-send-message
   #:player-send-prompt
   #:player-disconnect
   
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
