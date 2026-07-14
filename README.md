# Apeiron MUD - A Common Lisp MUD Server

A MUD (Multi-User Dungeon) server written in Common Lisp, inspired by Dworkin's Game Driver (DGD) and LMUD, with the added reckless capability of running lisp code at your own risk and peril (don't start a real server with this on the internet).

Very simple and raw at the moment, but the fact that it runs on lisp gives it some super powers, such as the ability to update the running image within the session.

## Architecture

```
       apeiron/core
     /     |        \
worlds  persistence  telnet
     \     |         /
         server
           |
       apeiron (meta)
```

Core is the shared foundation. Worlds and persistence build on it independently (no dependency between them). Telnet is standalone. The server layer wires everything together.

## Key Design Principles

1. **Persistent Objects** - Game objects are persisted and changes are logged to enable recovery (using BKNR.Datastore).
2. **All power to the user** - You can eval lisp code directly within the game (could/should be restricted to admins in the future)
3. **Hot Reloading** - No need to ever shut the server down for maintenance (WIP)

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
cd apeiron-mud

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
    (mud:create-room! tavern)
    (mud:create-room! forest)
    
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
- **cl-prevalence** - Persistence
- **fiveam** - Testing framework (optional)

All installed via Quicklisp automatically.

---

## World-Building Tutorial: Create a Secret Room

This tutorial walks you through creating a **password-protected secret room** containing a **secret diary** (guestbook).  
We'll use the in-game `eval` command, which runs Lisp code inside the live server — no restart required.

### The Plan

1. Create a hidden room: *The Ancient Library*
2. Create a secret diary (guestbook) and place it in the library
3. Connect the library to **the room you are standing in** through a *crack in the wall*
4. Lock the passage with a password challenge — players must `answer` correctly to enter

### Step-by-Step

#### 1. Connect to the server

```bash
telnet localhost 8888
```

Log in with any name. You'll start in the hub room, your current location.

#### 2. Create the secret room

Use `eval` to create a new room:

```
> eval (world-add-object! (world) (new-room :name "The Ancient Library" :description "A dusty hidden library lit by a single flickering candle. Shelves of crumbling books line the walls."))

#<MUD-ROOM The Ancient Library (ID: 12)>
```

The return value shows the new room and its world-level ID (yours will differ — note it for later).

#### 3. Create a secret diary (guestbook)

```
> eval (world-add-object! (world) (new-guestbook :name "a worn leather diary"))

#<MUD-GUESTBOOK a worn leather diary (ID: 13)>
```

#### 4. Place the diary in the secret room

```
> eval (container-add-object (world-object-by-id (world) 12) (world-object-by-id (world) 13))

#<MUD-GUESTBOOK a worn leather diary (ID: 13)>
```

Replace `12` and `13` with the IDs you got in steps 2 and 3.

#### 5. Connect the library to your current room

```
> eval (connect-rooms! (world) (here) "north" (world-object-by-id (world) 12) "south" :name "a crack in the wall")

#<MUD-CONNECTION a crack in the wall (ID: 14)>
```

A player in the hub room can now `go north` and find the crack, and a player in the library can `go south` back.

#### 6. Add the password challenge

Lock the connection with a password. Players must type `answer <password>` to pass:

```
> eval (connection-set-challenge (connection-find (here) "north") "The wall whispers: 'Speak the password.'" "open-sesame" "has-heard-secret")

NIL
```

This sets up three things on the *crack in the wall* connection:

| Property | Your value | Purpose |
|---|---|---|
| `challenge-question` | `"The wall whispers: 'Speak the password.'"` | Shown to players who try to pass without answering |
| `challenge-answer` | `"open-sesame"` | The correct answer (case-insensitive) |
| `challenge-flag` | `"has-heard-secret"` | A flag set on the player after a correct answer; once set, the player can pass freely |

#### 7. Test it

Try going north:

```
> go north

The wall whispers: 'Speak the password.'
```

Give the wrong answer:

```
> answer swordfish

Wrong answer. Try again.
```

Give the correct answer:

```
> answer open-sesame

Correct! The way forward opens.
```

Go north again — now you enter the library:

```
> go north
You go north.

=== The Ancient Library ===

A dusty hidden library lit by a single flickering candle. Shelves of crumbling books line the walls.

You see:
  - a worn leather diary (ID: 13)
  - Frodo (ID: 4)

Exits: south
```

#### 8. Read and write in the secret diary

```
> read diary

=== a worn leather diary ===

The diary is currently empty.

> write diary
What message do you want to write?
> Found the secret library at last!
You write your message in the diary.

> read diary

=== a worn leather diary ===

[2026-07-14 15:42:01] Frodo wrote:
  Found the secret library at last!
```

### Summary of Functions Used

| Function | Purpose |
|---|---|
| `new-room` | Create a new room |
| `new-guestbook` | Create a new guestbook (entries are persisted as CSV) |
| `world-add-object!` | Register an object/room in the world |
| `world-object-by-id` | Look up an object by its world-level ID |
| `container-add-object` | Place an object inside a container (room, player, etc.) |
| `connect-rooms!` | Create a bidirectional connection between two rooms |
| `connection-find` | Find the connection leaving a room in a given direction |
| `connection-set-challenge` | Lock a connection with a question/answer/flag challenge |
| `here` | Returns the current player's room (handy in `eval`) |
| `world` | Returns the current world (handy in `eval`) |

### Tips

- **Use `here` instead of IDs**: `(here)` returns the room you're standing in, so `(connect-rooms! (world) (here) "north" ...)` saves you from looking up IDs.
- **Check your work**: `(room-exit-list (here))` lists all exits from the current room.
- **All eval is persistent**: Every room, guestbook, and connection created this way is automatically saved to the BKNR datastore and survives server restarts.
- **Guestbook CSV persistence**: Guestbook entries are written to a CSV file in the `data/` directory and reloaded on server restart.

---

## Wordle Puzzle Game

A Wordle-like puzzle game you can drop into any room. Each puzzle has a secret 5-letter word, and players guess it by telling the puzzle their guesses. Each player's progress is tracked independently, so everyone can play simultaneously.

### Create a Wordle Puzzle

Use `eval` to create a puzzle and place it in your current room:

```
> eval (let ((p (new-wordle-puzzle)))
         (container-add-object (here) p)
         (create-object! (world) p))

#<MUD-WORDLE-PUZZLE a Wordle puzzle board (ID: 25)>
```

The puzzle uses today's **daily word** — determined by the current date, so all players see the same word each day and it changes daily. Create a puzzle with `eval` and drop it in your current room:

### Play the Game

Interact with the puzzle using the `tell` command (whisper privately to it — other players won't see your guesses):

| Command | What it does |
|---|---|
| `tell <puzzle> <word>` | Make a guess (e.g. `tell board crane`) |
| `tell <puzzle> help` | Show instructions and colour guide |
| `tell <puzzle> show` | Show the current puzzle state |

The puzzle responds with a colour-coded board:
- **Green** letters are correct and in the right position
- **Yellow** letters are in the word but in the wrong position
- **Dim** letters are not in the word at all

Example session:

```
> tell board train
The board glows with coloured pegs...

  t r a i n
  · · · · ·
  · · · · ·
  · · · · ·
  · · · · ·
  · · · · ·

Speak a 5-letter word aloud (5 guesses remaining)

> tell board crane

  t r a i n
  c r a n e
  · · · · ·
  · · · · ·
  · · · · ·
  · · · · ·

You solved it in 2 guesses! The word was: CRANE
```

When someone solves or fails the puzzle, other players in the room are notified:
```
Alice solved the Wordle puzzle!
```

### Advanced: Custom Puzzle

Create a puzzle with a specific word or custom settings:

```
> eval (let ((p (new-wordle-puzzle
                :name "Riddle Sphinx"
                :description "A wise stone sphinx awaits your guess."
                :target-word "quest"
                :max-guesses 4)))
         (container-add-object (here) p)
         (create-object! (world) p))

#<MUD-WORDLE-PUZZLE Riddle Sphinx (ID: 26)>
```

| Parameter | Default | Description |
|---|---|---|
| `:name` | `"a Wordle puzzle board"` | Display name of the puzzle |
| `:description` | *(default description)* | What players see when examining or viewing the board |
| `:target-word` | today's daily word | The 5-letter word to guess (omit for date-based daily word) |
| `:max-guesses` | `6` | How many guesses players get |
| `:word-list` | built-in ~500 words | A vector of valid 5-letter words to pick from |

### Reset a Puzzle

Reset all player progress (keeping the same word) or set a new word:

```
> eval (wordle-reset (world-object-with-name (world) "Riddle Sphinx"))

T

> eval (wordle-reset (world-object-with-name (world) "Riddle Sphinx") :new-word "magic")

T
```

### Admin: Place in a Specific Room

Find a room by name and place the puzzle there:

```
> eval (let ((p (new-wordle-puzzle :target-word "world"))
             (room (world-object-with-name (world) "The Gathering")))
         (container-add-object room p)
         (create-object! (world) p))

#<MUD-WORDLE-PUZZLE a Wordle puzzle board (ID: 27)>
```

### Persistence

Wordle puzzles are fully persistent. The word list and max guesses are saved to the BKNR datastore. Per-player guess state and the daily word are ephemeral (the puzzle recalculates its daily word on server restart). If you want a permanent fixed word, pass `:target-word` explicitly when creating the puzzle. To add a puzzle to the default world permanently, include it in the world builder function in `src/worlds/world-areas.lisp`.

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
