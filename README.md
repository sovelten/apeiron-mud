# Musical Guacamole - A Common Lisp MUD Server

A MUD (Multi-User Dungeon) server written in Common Lisp, inspired by Dworkin's Game Driver (DGD) and LMUD, with the added reckless capability of running lisp code at your own risk and peril (don't start a real server with this on the internet). The name was inspired by the first repository name that github suggested to me.

Very simple and raw at the moment, but the fact that it runs on lisp gives it some super powers, such as the ability to change the running image within the session.

## Inspiration

- **DGD Manual**: https://www.dworkin.nl/dgd/
- **LMUD**: https://lmud.common-lisp.dev/

## Table of Contents

1. [Quick Start (5 minutes)](#quick-start)
2. [Features](#features)
3. [Architecture](#architecture)
4. [Development Guide](#development-guide)
5. [Deployment](#deployment)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- **SBCL** (Steel Bank Common Lisp) 2.0+
- **Quicklisp** (Common Lisp package manager)

### Installation

```lisp
# Navigate to project directory
cd musical-guacamole

# In SBCL:
(push #p"./" asdf:*central-registry*)
(ql:quickload :mud)
```

### Start the Server

```lisp
# In SBCL:
(push #p"./" asdf:*central-registry*)
(ql:quickload :mud)
(mud:start-mud-server)
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

### Available Commands

| Command | Usage | Description |
|---------|-------|-------------|
| `look` | `look` | Examine current room |
| `go` | `go <direction>` | Move (north/south/east/west) |
| `exits` | `exits` | List available exits |
| `inventory` | `inventory` | View carried items |
| `say` | `say <message>` | Speak to other players in room |
| `help` | `help` | List all commands |
| `quit` | `quit` | Disconnect |
| `eval` | `eval <sexpr>` | Run arbritrary lisp code!!! (very dangerous) |

### Example Session 

Using eval to create a room:

```
What is your name?
> Frodo

=== The Tavern ===

You see:
  - Frodo (ID: 4)

Exits: north

Welcome to the MUD!
>  eval (mud:create-room! (mud:new-room :name "Valinor")) 
#<MUD-ROOM Valinor (ID: 5)>
> eval (mud:rooms)
(#<MUD-ROOM The Tavern (ID: 1)> #<MUD-ROOM A Dense Forest (ID: 2)>
 #<MUD-ROOM Valinor (ID: 5)>)
> eval (mud:room-add-exits (mud:room-by-id 1) :west (mud:room-by-id 5) :east)
#<MUD-ROOM The Tavern (ID: 1)>
> look

=== The Tavern ===

You see:
  - Frodo (ID: 4)

Exits: north, west

> go west
You go west.

=== Valinor ===

You see:
  - Frodo (ID: 4)

Exits: east

> say Where are all the elves?
You say: Where are all the elves?
> 
```

### Stop the Server

In the SBCL REPL:

```lisp
(mud:stop-mud-server)
```

---

## Features

### ✅ Currently Implemented

- **In-world REPL** - Execute Lisp code from within the game (at your own risk, no guardrails)
- **Multi-player networking** - Multiple players connect via telnet simultaneously
- **Object-oriented world** - Everything is an object with unique IDs and extensible properties
- **Persistence** - Objects are persisted through cl-prevalence in-memory database. Journaling enables recovery in case server needs to be shutdown.
- **Room system** - Navigable rooms with directional exits (north, south, east, west)
- **Player chat** - "say" command for in-room communication
- **Inventory system** - Foundation for item management
- **Command system** - 7 built-in commands, easy to add more

### 🎯 Planned Features

- **Hot code reloading** - Update system without restarting
- **Item system** - Full item objects with properties (take, drop, examine)
- **NPC support** - Non-player characters with behaviors
- **LLM NPCs** - What if we put in some llms armed with some mcp servers to interact in the world?

---

## Architecture

### Core System Components

#### Object System (`src/object.lisp`)
Everything in the MUD is a `mud-object`:
- **Unique ID**: Auto-generated, thread-safe
- **Name**: Display name
- **Type**: Classification (room, player, item, etc.)
- **Location**: Where the object is
- **Properties**: Extensible hash-table for custom data

#### Room System
Rooms are specialized objects:
- **Contents**: Array of objects in the room
- **Exits**: Hash map of directional exits (north → room-id, etc.)
- **Description**: Room appearance

#### Player System (`src/player.lisp`)
Players are specialized objects:
- **Socket**: Network connection to client
- **Inventory**: Array of carried objects
- **Location**: Current room

#### Command System (`src/command-handler.lisp`)
Simple macro-based command definition:
```lisp
(define-command "command-name" (player args)
  ;; Command implementation
  )
```

#### World System (`src/world.lisp`)
Global state management:
- Room registry and lookup
- Player tracking
- Message broadcasting
- World initialization

#### Network System (`src/network.lisp`)
- TCP server (default: 127.0.0.1:8888)
- Accepts incoming connections
- Per-player threading
- Socket management and cleanup

### Data Flow: Command Processing

```
Telnet Input ("go north")
  ↓
parse-command: Extract command and arguments
  ↓
process-command: Lookup handler in *commands* hash table
  ↓
Execute Handler: "go" command runs
  ├─ Get current room
  ├─ Look up exit
  ├─ Move player
  └─ Send messages
  ↓
Telnet Output: Room description + prompt
```

### Key Design Principles

1. **Persistent Objects** - Game objects are persisted and changes are logged to enable recovery.
2. **All power to the user** - You can eval lisp code directly within the game (could/should be restricted to admins in the future)
3. **Hot Reloading** - No need to ever shut the server down for maintenance (WIP)

## Development Guide

### Adding a New Command

Commands are defined in `src/command-handler.lisp` using the `define-command` macro:

```lisp
(define-command "wave" (player args)
  (player-send-message player "You wave your hand."))
```

The macro takes:
- **Name**: Command string (will be lowercased)
- **Parameters**: `player` (the player object) and `args` (raw argument string)
- **Body**: Command implementation

### Example: More Complex Command

```lisp
(define-command "examine" (player args)
  (let ((obj-name (string-trim '(#\Space #\Tab) args)))
    (if (zerop (length obj-name))
        (player-send-message player "Examine what?")
        (player-send-message player (format nil "You examine the ~A." obj-name)))))
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
                 :id (mud.utils:make-id)
                 :name name
                 :type 'weapon
                 :damage damage
                 :weight weight))
```

### Using Object Properties

Objects have a flexible property storage system:

```lisp
;; Set properties
(object-set-property player "experience" 1000)
(object-set-property room "dark" t)

;; Get properties
(object-get-property player "experience")  ; → 1000
(object-get-property room "dark")          ; → T
```

### Building World Content

```lisp
;; Create rooms
(defun build-world ()
  (let ((tavern (mud:new-room :name "The Tavern"))
        (forest (mud:new-room :name "A Dense Forest")))
    
    ;; Register rooms
    (mud:world-add-room tavern)
    (mud:world-add-room forest)
    
    ;; Connect rooms
    (mud:room-add-exit tavern "north" forest)
    (mud:room-add-exit forest "south" tavern)
    
    ;; Set descriptions
    (object-set-property tavern "description" 
      "A cozy tavern filled with travelers.")
    (object-set-property forest "description"
      "A dense forest with tall trees.")))
```

### Broadcasting Messages

Send messages to all players:

```lisp
;; Message to all players
(world-broadcast "A loud bell rings!")

;; Message to all except one
(world-broadcast "A wizard teleports away!" except-player)
```

### Timed Events

Use threading for periodic events:

```lisp
(defun start-world-heartbeat (interval)
  "Update world every INTERVAL seconds."
  (bordeaux-threads:make-thread
    (lambda ()
      (loop while mud:*server-running* do
        (sleep interval)
        ;; Update logic here
        (dolist (room (mud:rooms))
          ;; Do something with each room
          )))
    :name "world-heartbeat"))
```

### Testing Commands

```lisp
(ql:quickload :mud/tests)
(mud.tests:run-tests)
```

Or load run-tests.lisp:

```bash
sbcl --non-interactive --load run-tests.lisp
```

---

## Deployment

### Configuration

Edit `src/constants.lisp`:

```lisp
(defconstant +server-host+ "127.0.0.1")  ; Change host
(defconstant +server-port+ 8888)         ; Change port
(defconstant +max-command-length+ 1024)  ; Max input length
```

### Server Monitoring

```lisp
;; Check status
(mud:status)

;; Get running players
(mud:characters)

;; Get all rooms
(mud:rooms)
```

### Stopping the Server

```lisp
(mud:stop)
```

This:
1. Sets `*server-running*` to NIL
2. Closes the server socket
3. Waits for acceptance thread to exit
4. Disconnects all players

---

## Dependencies

- **usocket** - Network communication
- **bordeaux-threads** - Multi-threading
- **fiveam** - Testing framework (optional)

All installed via Quicklisp automatically.

---

## Troubleshooting

### "Cannot find system :mud"

Make sure `mud.asd` is in the current directory and you've added it to ASDF:

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
```
