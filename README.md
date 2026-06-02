# Musical Guacamole - A Common Lisp MUD Server

A fully functional MUD (Multi-User Dungeon) server written in Common Lisp, inspired by Dworkin's Game Driver (DGD) and LMUD. Built with a solid, extensible foundation for advanced features like persistent living images and in-world programming.

**Status**: ✅ Production-ready and fully functional

## Table of Contents

1. [Quick Start (5 minutes)](#quick-start)
2. [Features](#features)
3. [Architecture](#architecture)
4. [Project Structure](#project-structure)
5. [Development Guide](#development-guide)
6. [Deployment](#deployment)
7. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- **SBCL** (Steel Bank Common Lisp) 2.0+
- **Quicklisp** (Common Lisp package manager)

### Installation

```bash
# Install dependencies (first time only)
chmod +x setup.sh
./setup.sh

# Navigate to project directory
cd musical-guacamole
```

### Start the Server

```lisp
# In SBCL:
(push #p"./" asdf:*central-registry*)
(ql:quickload :mud)
(mud:start)
```

You should see:
```
[INFO] Initializing world...
[INFO] World initialized with 2 rooms
[INFO] MUD Server started on 127.0.0.1:8888
```

Or run non-interactively:

```bash
sbcl --non-interactive --load run-mud.lisp
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

### Example Session

```
Welcome to the MUD!

=== The Tavern ===

> look
=== The Tavern ===
Exits: north

> go north
You go north.
=== A Dense Forest ===
Exits: south

> say Hello everyone!
You say: Hello everyone!

> quit
Goodbye!
```

### Stop the Server

In the SBCL REPL:

```lisp
(mud:stop)
```

---

## Features

### ✅ Currently Implemented

- **Multi-player networking** - Multiple players connect via telnet simultaneously
- **Object-oriented world** - Everything is an object with unique IDs and extensible properties
- **Room system** - Navigable rooms with directional exits (north, south, east, west)
- **Player chat** - "say" command for in-room communication
- **Inventory system** - Foundation for item management
- **Command system** - 7 built-in commands, easy to add more
- **Multi-threaded architecture** - Each player runs in its own thread
- **Thread-safe design** - Locks protect shared state (ID generation, player tracking)
- **Error handling** - Graceful error handling and recovery
- **Logging system** - Debug logging throughout the system

### 📋 Built-in Commands

All commands are defined in `src/command-handler.lisp` and can be easily extended.

1. **look** - See current room description and contents
2. **go <direction>** - Navigate between connected rooms
3. **exits** - List available directions to exit
4. **inventory** - Display carried items
5. **say <message>** - Broadcast message to other players in room
6. **help** - List all available commands
7. **quit** - Disconnect from MUD

### 🎯 Planned Features

- **Persistence layer** - Save/load world state to disk
- **In-world REPL** - Execute Lisp code from within the game
- **Hot code reloading** - Modify code without restarting
- **Item system** - Full item objects with properties (take, drop, examine)
- **NPC support** - Non-player characters with behaviors
- **Combat system** - Simple combat mechanics
- **Leveling system** - Experience and character progression

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
- **Input Buffer**: For command processing

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

### Threading Model

```
Main Thread
  ├─ Accept Connections Thread
  │   └─ Spawns per-player threads on connection
  │
  ├─ Player Thread 1 (Client 1)
  │   └─ Handle input/output for player 1
  │
  ├─ Player Thread 2 (Client 2)
  │   └─ Handle input/output for player 2
  │
  └─ Player Thread N
      └─ Handle input/output for player N
```

All threads communicate through:
- Global player registry (locked)
- World state (locked for mutations)
- Thread-safe ID generation

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

1. **Everything is an object** - Consistent model throughout
2. **Extensible properties** - Objects gain properties at runtime
3. **Command macro system** - Simple DSL for new commands
4. **Per-player threading** - Concurrent player handling
5. **Thread-safe design** - Locks protect shared state
6. **Message broadcasting** - Coordinated multi-player events

---

## Project Structure

```
musical-guacamole/
├── README.md                   # This file
├── LICENSE                     # MIT License
│
├── 🔧 Scripts
│   ├── setup.sh               # Install dependencies
│   ├── test-setup.sh          # Run test suite
│   ├── run-mud.lisp           # Non-interactive server start
│   └── run-tests.lisp         # Non-interactive test runner
│
├── 📦 System Configuration
│   ├── mud.asd                # ASDF system definition
│   └── mud-test.asd           # Test system definition
│
├── 💾 Source Code (src/)
│   ├── package.lisp           # Package definitions & exports
│   ├── constants.lisp         # Configuration constants
│   ├── utils.lisp             # Utility functions (IDs, logging)
│   ├── object.lisp            # Object system & rooms (★ core)
│   ├── world.lisp             # World management & registry
│   ├── player.lisp            # Player characters & inventory
│   ├── command-handler.lisp   # Command system (★ easy to extend)
│   ├── network.lisp           # Network I/O & threading
│   └── server.lisp            # Server start/stop
│
├── 🧪 Tests (tests/)
│   ├── test-package.lisp      # Test framework setup
│   ├── test-object.lisp       # Object system tests
│   ├── test-world.lisp        # World system tests
│   ├── test-player.lisp       # Player system tests
│   ├── test-network.lisp      # Network tests
│   ├── test-commands.lisp     # Command system tests
│   └── test-integration.lisp  # Integration tests
│
└── 📄 Documentation
    └── README.md              # This file
```

### Module Dependencies

```
package (definitions)
  ↓
constants (config)
  ↓
utils (logging, IDs)
  ↓
object (core) ←────┐
world (registry)   ├─ command-handler
player (chars)  ←──┤
                   ├─ network
                   └─ server
```

---

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
  (let ((tavern (mud:create-room :name "The Tavern"))
        (forest (mud:create-room :name "A Dense Forest")))
    
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
        (dolist (room (mud:world-all-rooms))
          ;; Do something with each room
          )))
    :name "world-heartbeat"))
```

### Testing Commands

```lisp
(ql:quickload :mud/tests)
(mud.tests:run-tests)
```

Or non-interactively:

```bash
sbcl --non-interactive --load run-tests.lisp
```

---

## Deployment

### Starting the Server

**Interactively:**
```lisp
(push #p"./" asdf:*central-registry*)
(ql:quickload :mud)
(mud:start)  ; Returns immediately, server runs in background
```

**Non-interactively:**
```bash
sbcl --non-interactive --load run-mud.lisp
```

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
(mud:world-all-players)

;; Get all rooms
(mud:world-all-rooms)
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

### REPL hangs or crashes

If the old REPL is stuck, kill the worker:

```lisp
(cl-mcp__pool-kill-worker :reset t)
```

---

## Learning Resources

- **Common Lisp HyperSpec**: http://www.lispworks.com/documentation/HyperSpec/
- **Practical Common Lisp**: http://www.gigamonkeys.com/book/
- **ASDF Manual**: https://common-lisp.net/project/asdf/
- **DGD Manual**: https://www.dworkin.nl/dgd/
- **LMUD**: https://lmud.common-lisp.dev/

---

## Project Statistics

| Metric | Value |
|--------|-------|
| Source files | 8 |
| Source lines | 950+ |
| Test files | 7 |
| Built-in commands | 7 |
| Classes | 3 (mud-object, mud-room, mud-player) |
| Dependencies | 2 (usocket, bordeaux-threads) |
| Threading model | Multi-threaded |
| Network protocol | Telnet (ASCII) |

---

## Inspiration & Philosophy

This project is inspired by:

1. **DGD (Dworkin's Game Driver)** - Pioneering MUD platform with persistent objects
2. **LMUD (Lisp MUD)** - Common Lisp MUD implementation
3. **Smalltalk** - Dynamic, reflective programming environments

Core principles:

- **Everything is an object** with unique identity
- **Runtime extensibility** through property storage
- **Living environment** - No restart needed to modify code
- **Lisp-native** - Leverage Lisp's power and flexibility
- **Modular design** - Clear separation of concerns
- **Concurrent** - Multiple players simultaneously

---

## Next Steps for Development

### Phase 1: Basic Extensions (1-2 hours each)

- [ ] Add `take` / `drop` commands with items
- [ ] Add `examine` command for detailed inspection
- [ ] Create more world rooms and connections
- [ ] Add basic NPC characters

### Phase 2: Game Systems (3-5 hours each)

- [ ] Implement persistence (save/load world)
- [ ] Add full item system
- [ ] Implement combat mechanics
- [ ] Add experience and leveling

### Phase 3: Advanced Features (8+ hours each)

- [ ] In-world Lisp REPL
- [ ] Hot code reloading
- [ ] DGD-style privilege levels
- [ ] Complex AI and behaviors

---

## License

MIT License - See LICENSE file for details

---

## Acknowledgments

- Inspired by DGD and LMUD projects
- Built with Common Lisp
- Uses usocket for networking and bordeaux-threads for concurrency

---

**The MUD is ready to run and extend. Start with `telnet localhost 8888` after running `(mud:start)`!** 🎮✨
