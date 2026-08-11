;;;; docs/apeiron-manual.lisp — content sections for the Apeiron manual.
;;;;
;;;; Prose sections migrated from the hand-written README: getting
;;;; started, features, architecture, development guide, deployment,
;;;; troubleshooting, and the tutorials (included from markdown files
;;;; so they can be edited independently).

(in-package #:apeiron-docs)

(named-readtables:in-readtable pythonic-string-syntax)

(defsection @getting-started (:title "Getting Started")
  """### Prerequisites

  - **SBCL** 2.0+
  - **Quicklisp**

  ### Start the Server

  In SBCL:

  ```lisp
  (push #p"./" asdf:*central-registry*)
  (ql:quickload :apeiron)
  (apeiron.server:start-mud-server)
  ```

  Or load run-mud.lisp:

  ```bash
  sbcl --load run-mud.lisp
  ```

  You should see:

  ```
  [INFO] Initializing world...
  [INFO] World initialized with 2 rooms
  [INFO] MUD Server started on 127.0.0.1:8888
  ```

  ### Connect as a Player

  In another terminal:

  ```bash
  telnet localhost 8888
  ```

  ### Example Session

  > **Note:** the in-game `eval` command is restricted. Only characters
  > owned by an **admin** account, or characters wearing an object with
  > both the `hat` and `wizard` keywords (a "wizard hat"), may use it.

  Using eval to create a room and connect it:

  ```
  What is your name?
  > Frodo

  === The Prancing Pony ===

  You see:
    - Frodo (ID: 4)

  Exits: west

  Welcome to the MUD!
  > eval (world-add-object! (world) (new-room :name "Rivendell"))
  #<MUD-ROOM Rivendell (ID: 8)>
  > eval (connect-rooms! (world) (here) "east" (world-object-with-name (world) "Rivendell") "west")
  #<MUD-CONNECTION passage between The Prancing Pony and Rivendell (ID: 9)>
  > look

  === The Prancing Pony ===

  You see:
    - Frodo (ID: 4)

  Exits: west, east

  > go east
  You go east.

  === Rivendell ===

  You see:
    - Frodo (ID: 4)

  Exits: west

  > say Where are all the elves?
  You say: Where are all the elves?
  ```

  ### Stop the Server

  In the SBCL REPL:

  ```lisp
  (apeiron.server:stop-mud-server)
  ```

  This:
  1. Sets `*server-running*` to NIL
  2. Closes the server socket
  3. Waits for acceptance thread to exit
  4. Disconnects all characters""")

(defsection @features (:title "Features")
  """### Currently Implemented

  - **In-world REPL** — execute Lisp code from within the game (at your own risk, no guardrails)
  - **Multi-player networking** — multiple players connect via telnet simultaneously
  - **Object-oriented world** — everything is an object with unique IDs and extensible properties
  - **Persistence** — objects are persisted through the BKNR datastore; journaling enables recovery in case the server needs to be shut down
  - **Room system** — navigable rooms with directional exits (north, south, east, west)
  - **Player chat** — `say` command for in-room communication
  - **Inventory system** — foundation for item management
  - **Command system** — 17 built-in commands, easy to add more

  ### Planned

  - Hot code reloading — update the system without restarting
  - Full item system — items with properties (take, drop, examine)
  - NPC support — non-player characters with behaviors
  - LLM NPCs — NPCs backed by LLMs, armed with MCP servers""")

(defsection @architecture (:title "Architecture")
  """```
         apeiron/core
       /     |        \
  worlds  persistence  telnet
       \     |         /
           server
             |
         apeiron (meta)
  ```

  Core is the shared foundation. Worlds and persistence build on it
  independently (no dependency between them). Telnet is standalone.
  The server layer wires everything together.

  ### Key Design Principles

  1. **Persistent Objects** — game objects are persisted and changes are
     logged to enable recovery (using BKNR.Datastore).
  2. **All power to the user** — you can eval Lisp code directly within
     the game (could/should be restricted to admins in the future).
  3. **Hot Reloading** — no need to ever shut the server down for
     maintenance (WIP).""")

(defsection @protocols (:title "Protocols")
  """- **Telnet (RFC 854)** — network protocol for player connections, with
    option negotiation, line editing and echo control
    (see `apeiron/telnet`).
  - **MSSP** — MUD Server Status Protocol: advertises server details
    (name, players, game type, ...) to directory services.
  - **TLS** — secure transport for telnet connections (via `cl+ssl`).
  - **ANSI SGR colors** — colour output for the client (toggle with
    `toggle-colors`).""")

(defsection @development (:title "Development Guide")
  """### Adding a New Command

  Commands are defined in `src/command-handler.lisp` using the
  DEFINE-COMMAND macro:

  ```lisp
  (define-command "wave" (world character args)
    (declare (ignore world args))
    (character-send-message character "You wave your hand."))
  ```

  The macro takes:
  - **Name**: command string (will be lowercased)
  - **Parameters**: `world` (the mud-world instance), `character` (the character object), and `args` (raw argument string)
  - **Body**: command implementation

  ### Example: More Complex Command

  ```lisp
  (define-command "examine" (world character args)
    (declare (ignore world))
    (let ((obj-name (string-trim '(#\Space #\Tab) args)))
      (if (zerop (length obj-name))
          (character-send-message character "Examine what?")
          (character-send-message character (format nil "You examine the ~A." obj-name)))))
  ```

  ### Creating New Object Types

  Extend the `mud-object` class:

  ```lisp
  (defclass mud-weapon (mud-object)
    ((damage :initarg :damage
             :accessor weapon-damage
             :initform 5)
     (weight :initarg :weight
             :accessor weapon-weight
             :initform 2)))

  (defun create-weapon (&key (name "sword") (damage 5) (weight 2))
    (make-instance 'mud-weapon
                   :name name
                   :damage damage
                   :weight weight))
  ```

  ### Using Object Properties

  Objects have a flexible property storage system:

  ```lisp
  ;; Set properties
  (object-set-property character "experience" 1000)
  (object-set-property room "dark" t)

  ;; Get properties
  (object-get-property character "experience")  ; → 1000
  (object-get-property room "dark")          ; → T
  ```

  ### Building World Content

  ```lisp
  ;; Create rooms
  (defun build-world (world)
    (let ((tavern (new-room :name "The Tavern"
                            :description "A cozy tavern filled with travelers."))
          (forest (new-room :name "A Dense Forest"
                            :description "A dense forest with tall trees.")))

      ;; Register rooms in the world
      (world-add-object! world tavern)
      (world-add-object! world forest)

      ;; Connect rooms
      (connect-rooms! world tavern "north" forest "south")))
  ```

  ### Broadcasting Messages

  ```lisp
  ;; Message to all characters
  (world-broadcast "A loud bell rings!")

  ;; Message to all except one
  (world-broadcast "A wizard teleports away!" except-character)
  ```

  ### Testing Commands

  ```lisp
  (ql:quickload :apeiron-test)
  (apeiron-test:run-tests)
  ```

  Or load run-tests.lisp:

  ```bash
  sbcl --non-interactive --load run-tests.lisp
  ```""")

(defsection @tutorial-secret-room (:title "Tutorial: Create a Secret Room")
  (secret-room (include #.(asdf:system-relative-pathname
                           :apeiron-docs "docs/tutorial-secret-room.md"))))

(defsection @tutorial-wordle (:title "Tutorial: Wordle Puzzle Game")
  (wordle (include #.(asdf:system-relative-pathname
                       :apeiron-docs "docs/tutorial-wordle.md"))))

(defsection @deployment (:title "Deployment")
  """### Configuration

  Edit `src/constants.lisp`:

  ```lisp
  (defconstant +server-host+ "127.0.0.1")  ; Change host
  (defconstant +server-port+ 8888)         ; Change port
  (defconstant +max-command-length+ 1024)  ; Max input length
  ```

  ### Server Monitoring

  ```lisp
  ;; Check status
  (apeiron.server:get-server-status)

  ;; Get running characters
  (apeiron.core:characters (apeiron.persistence:get-persistent-world))

  ;; Get all rooms
  (apeiron.core:world-all-rooms (apeiron.persistence:get-persistent-world))
  ```

  ### Stopping the Server

  ```lisp
  (apeiron.server:stop-mud-server)
  ```""")

(defsection @troubleshooting (:title "Troubleshooting")
  """### "Cannot find system :apeiron"

  Make sure `apeiron.asd` is in the current directory and you've added
  it to ASDF:

  ```lisp
  (push #p"./" asdf:*central-registry*)
  ```

  ### "Address already in use" (Port 8888)

  Either:
  1. Wait a minute for the port to be released
  2. Change the port in `src/constants.lisp`
  3. Kill the old process: `pkill -f sbcl`

  ### Cannot connect with telnet

  Verify:
  1. Server is running (check SBCL output)
  2. Port is correct (default 8888)
  3. No firewall blocking connections
  4. Try: `telnet 127.0.0.1 8888`

  ### Dependency installation fails

  Manually install dependencies:

  ```lisp
  (ql:quickload (list "usocket" "bordeaux-threads" "fiveam"))
  ```""")

(defsection @dependencies (:title "Dependencies")
  """- **usocket** — network communication
  - **bordeaux-threads** — multi-threading
  - **flexi-streams** — stream encoding
  - **cl+ssl** — TLS support
  - **ironclad** — cryptography (password hashing)
  - **log4cl** — logging
  - **str** — string utilities
  - **cl-csv** — guestbook CSV persistence
  - **cl-graph** — area graph algorithms
  - **deeds** — event system
  - **bknr.datastore** — persistence
  - **fiveam** — testing (optional)

  All installed via Quicklisp automatically.""")

(defsection @mcp (:title "MCP Server (LLM Integration)")
  """An [MCP (Model Context Protocol)](https://spec.modelcontextprotocol.io/)
  server is included in `mcp/`. It lets an LLM (Claude, Continue, etc.)
  connect to the MUD as a player character, issue commands, and run Lisp
  code in the game world.

  See [mcp/README.md](https://github.com/sovelten/apeiron-mud/blob/main/mcp/README.md)
  for setup and usage.""")

(defsection @command-reference (:title "Command Reference")
  """| Command | Usage | Description |
  |---------|-------|-------------|
  | `look` | `look` | Examine current room |
  | `go` | `go <direction>` | Move (north/south/east/west) |
  | `exits` | `exits` | List available exits |
  | `inventory` | `inventory` | View carried items |
  | `examine` | `examine <name>` | Examine an object or NPC |
  | `attack` | `attack <name>` | Attack an NPC |
  | `say` | `say <message>` | Speak to other characters in room |
  | `shout` | `shout <message>` | Broadcast to all characters |
  | `tell` | `tell <name> <message>` | Private message to a character or object |
  | `read` | `read <name>` | Read a readable object (guestbook, sign, etc.) |
  | `write` | `write <name>` | Write a message on a writable object |
  | `answer` | `answer <text>` | Answer a challenge/puzzle |
  | `status` | `status` | Show your HP and stats |
  | `help` | `help` | List all commands |
  | `toggle-colors` | `toggle-colors` | Toggle ANSI color output |
  | `eval` | `eval <sexpr>` | Run arbitrary lisp code (admin only!) |
  | `quit` | `quit` | Disconnect |""")
