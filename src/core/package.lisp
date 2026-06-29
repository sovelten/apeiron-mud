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

   ;; ANSI color control
   #:*colorize*

   ;; ANSI color constants
   #:+sgr-reset+
   #:+sgr-bold+
   #:+sgr-dim+
   #:+sgr-italic+
   #:+sgr-underline+
   #:+sgr-blink+
   #:+sgr-reverse+
   #:+sgr-fg-black+
   #:+sgr-fg-red+
   #:+sgr-fg-green+
   #:+sgr-fg-yellow+
   #:+sgr-fg-blue+
   #:+sgr-fg-magenta+
   #:+sgr-fg-cyan+
   #:+sgr-fg-white+
   #:+sgr-bg-black+
   #:+sgr-bg-red+
   #:+sgr-bg-green+
   #:+sgr-bg-yellow+
   #:+sgr-bg-blue+
   #:+sgr-bg-magenta+
   #:+sgr-bg-cyan+
   #:+sgr-bg-white+
   #:+sgr-fg-bright-black+
   #:+sgr-fg-bright-red+
   #:+sgr-fg-bright-green+
   #:+sgr-fg-bright-yellow+
   #:+sgr-fg-bright-blue+
   #:+sgr-fg-bright-magenta+
   #:+sgr-fg-bright-cyan+
   #:+sgr-fg-bright-white+
   #:+sgr-bg-bright-black+
   #:+sgr-bg-bright-red+
   #:+sgr-bg-bright-green+
   #:+sgr-bg-bright-yellow+
   #:+sgr-bg-bright-blue+
   #:+sgr-bg-bright-magenta+
   #:+sgr-bg-bright-cyan+
   #:+sgr-bg-bright-white+

   ;; ANSI color helpers
   #:color-text
   #:bold
   #:underline
   #:red
   #:green
   #:yellow
   #:blue
   #:magenta
   #:cyan
   #:white
   #:bright-red
   #:bright-green
   #:bright-yellow
   #:bright-blue
   #:bright-magenta
   #:bright-cyan
   #:bright-white
   #:bold-red
   #:bold-green
   #:bold-yellow
   #:bold-cyan
   #:bold-white

   ;; Object system
   #:mud-object
   #:new-object
   #:object-id
   #:object-name
   #:object-description
   #:object-describe
   #:object-location
   #:object-properties
   #:object-type
   #:object-get-property
   #:object-set-property
   #:object-move

   ;; NPC / Combat
   #:mud-npc
   #:new-npc
   #:npc-hp
   #:npc-max-hp
   #:npc-attack-min
   #:npc-attack-max
   #:npc-defeated-p
   #:npc-defeat!
   #:npc-defeat-message
   #:npc-victory-flag
   #:npc-roll-attack
   #:npc-describe
   #:find-npc-in-room
   #:combat-attack-npc
   #:room-challenge-blocked-p
   #:room-exit-blocked-p
   #:player-hp
   #:player-max-hp
   #:player-ensure-combat-stats
   #:build-shopping-mall
   #:build-team-rocket-cavern

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
   #:session-use-colors

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
