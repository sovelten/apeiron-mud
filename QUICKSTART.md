# Quickstart Guide for Musical Guacamole MUD

## Prerequisites

- **SBCL** (Steel Bank Common Lisp) - version 2.0 or later
- **Quicklisp** - Common Lisp package manager

### Installation

#### On Ubuntu/Debian:
```bash
sudo apt-get install sbcl
```

#### On macOS (with Homebrew):
```bash
brew install sbcl
```

#### Install Quicklisp:
Download and install from https://www.quicklisp.org/beta/

## Initial Setup

1. Clone or download this repository
2. Run the setup script (optional, but recommended):
```bash
chmod +x setup.sh
./setup.sh
```

This will install the required dependencies (usocket, bordeaux-threads, fiveam).

## Starting the MUD Server

**IMPORTANT:** You must be in the project directory first!

```bash
cd /path/to/musical-guacamole
```

Then open SBCL and run:

```lisp
(push #p"/path/to/musical-guacamole/" asdf:*central-registry*)
(ql:quickload :mud)
(mud:start)
```

**Replace `/path/to/musical-guacamole/` with your actual project path.**

Example (if you're in the project directory):

```lisp
(push (uiop:getcwd) asdf:*central-registry*)
(ql:quickload :mud)
(mud:start)
```

You should see:
```
[INFO] Initializing world...
[INFO] World initialized with 2 rooms
[INFO] MUD Server started on 127.0.0.1:8888
```

The server is now running and waiting for connections!

## Connecting as a Player

In another terminal, use telnet to connect:

```bash
telnet localhost 8888
```

You'll see a welcome message and the description of the starting room (The Tavern).

## Available Commands

| Command | Usage | Description |
|---------|-------|-------------|
| `look` | `look` | Look around your current room |
| `go` | `go <direction>` | Move in a direction (e.g., `go north`) |
| `exits` | `exits` | See available exits from current room |
| `inventory` | `inventory` | See what you're carrying |
| `say` | `say <message>` | Speak to others in the room |
| `help` | `help` | List all available commands |
| `quit` | `quit` | Disconnect from the MUD |

### Example Session

```
Welcome to the MUD!

=== The Tavern ===

You see:

Exits: north

> look

=== The Tavern ===

You see:

Exits: north

> go north
You go north.

=== A Dense Forest ===

You see:

Exits: south

> go south
You go south.

=== The Tavern ===

You see:

Exits: north

> say Hello everyone!
You say: Hello everyone!

> quit
Goodbye!
Connection closed.
```

## Stopping the Server

In the SBCL REPL where you started the server, run:

```lisp
(mud:stop)
```

## Checking Server Status

```lisp
(mud:status)
```

Output:
```
Server running: Yes
Players online: 3
Rooms in world: 2
```

## Architecture

### Core Modules

- **package.lisp** - Package definitions and exports
- **constants.lisp** - Configuration and constants
- **utils.lisp** - Utility functions (ID generation, logging)
- **object.lisp** - Base MUD object system and room handling
- **world.lisp** - World management and room registration
- **player.lisp** - Player character and inventory system
- **command-handler.lisp** - Command parsing and built-in commands
- **network.lisp** - Network communication and threading
- **server.lisp** - Server startup/shutdown

### Object Hierarchy

```
mud-object (base class)
├── mud-room (locations in the game world)
└── mud-player (player characters)
```

### Key Features

- **Object-oriented world** - Everything is an object with properties
- **Unique IDs** - Each object has a unique identifier
- **Extensible properties** - Store arbitrary data on objects using hash tables
- **Multi-threaded** - Each player connection runs in its own thread
- **Room system** - Navigable rooms with directional exits
- **Command system** - Easy to add new commands with a macro

## Troubleshooting

### "Cannot find system :mud"
Make sure you're in the `musical-guacamole` directory and that `mud.asd` is present.

### "Cannot find component usocket"
The dependencies aren't installed. Run:
```lisp
(ql:quickload (list "usocket" "bordeaux-threads"))
```

### "Address already in use"
Another process is using port 8888. Either:
- Wait a minute for the port to be released
- Edit `src/constants.lisp` to use a different port

### Cannot connect with telnet
Make sure the server is running (you should see the startup message in SBCL).

## Next Steps for Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for information on:
- Adding new commands
- Creating new object types
- Building world content
- Extending the system

## Learning Resources

- [Common Lisp HyperSpec](http://www.lispworks.com/documentation/HyperSpec/)
- [Practical Common Lisp](http://www.gigamonkeys.com/book/) - Free online book
- [ASDF Manual](https://common-lisp.net/project/asdf/)
- [DGD MUD Driver](https://www.dworkin.nl/dgd/) - Our primary inspiration
- [LMUD](https://lmud.common-lisp.dev/) - Another Lisp MUD implementation
