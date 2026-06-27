;;;; src/core/package.lisp — Package definitions for the Apeiron core module

(defpackage #:apeiron.core.utils
  (:use #:cl)
  (:export
   #:make-id
   #:format-message
   #:log-message
   #:log-error))

(defpackage #:apeiron.core
  (:use #:cl
        #:apeiron.core.utils
        #:bordeaux-threads
        #:cl-csv)
  (:export
   ;; Core version / debug
   #:*mud-version*
   #:*debug-mode*

   ;; Object type constants
   #:+object-type-generic+
   #:+object-type-room+
   #:+object-type-character+
   #:+object-type-item+

   ;; Command constants
   #:+max-command-length+
   #:+command-timeout+

   ;; Object system
   #:mud-object
   #:new-object
   #:object-id
   #:object-name
   #:object-description
   #:object-describe
   #:object-location
   #:object-properties
   #:object-get-property
   #:object-set-property
   #:object-move

   ;; Room system
   #:mud-room
   #:new-room
   #:room-contents
   #:room-add-object
   #:room-remove-object
   #:room-exits
   #:room-add-exit
   #:room-add-exits
   #:room-get-exit
   #:room-describe

   ;; Guestbook
   #:mud-guestbook
   #:new-guestbook
   #:guestbook-filepath
   #:guestbook-entries
   #:guestbook-load-from-csv
   #:guestbook-append-entry-to-csv
   #:guestbook-add-entry
   #:guestbook-format-entries

   ;; Session protocols / base
   #:mud-read-line
   #:mud-write
   #:session-stream
   #:session-keepalive
   #:session-disconnect

   ;; Session classes
   #:mud-session
   #:new-session
   #:session-id
   #:session-character

   #:stream-session

   ;; Session helpers
   #:session-send-prompt
   #:read-line-with-timeout-loop
   #:ask-input

   ;; Character
   #:mud-character
   #:new-character
   #:character-session
   #:player-inventory
   #:character-inventory-add
   #:character-inventory-remove
   #:player-send-message

   ;; World
   #:mud-world
   #:new-world
   #:world-id-counter
   #:world-config
   #:world-players
   #:world-objects
   #:world-rooms
   #:get-config-key
   #:world-gen-id!
   #:world-set-object-id!
   #:world-set-starting-room!
   #:starting-room
   #:world-add-character!
   #:world-total-players
   #:world-remove-character!
   #:character-by-id
   #:characters
   #:find-character-in-room
   #:world-broadcast
   #:world-object-by-id
   #:world-object-with-name
   #:world-all-objects
   #:world-room-by-id
   #:world-total-rooms

   ;; Command system
   #:*commands*
   #:define-command
   #:parse-command
   #:process-command))
