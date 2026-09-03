<a id="x-28APEIRON-DOCS-3A-40README-2040ANTS-DOC-2FLOCATIVES-3ASECTION-29"></a>

# Apeiron

Apeiron is a `MUD` server written in Common Lisp, inspired by
Dworkin's Game Driver (`DGD`) and `LMUD`, with the reckless capability of
running Lisp code inside the game world.

[![](https://github.com/sovelten/apeiron-mud/actions/workflows/test.yml/badge.svg)][b83b]

<a id="x-28APEIRON-DOCS-3A-40GETTING-STARTED-2040ANTS-DOC-2FLOCATIVES-3ASECTION-29"></a>

## Getting Started

<a id="prerequisites"></a>

### Prerequisites

* **`SBCL`** 2.0+
* **Quicklisp**

<a id="start-the-server"></a>

### Start the Server

In `SBCL`:

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
<a id="connect-as-a-player"></a>

### Connect as a Player

In another terminal:

```bash
telnet localhost 8888
```
<a id="example-session"></a>

### Example Session

> **Note:** the in-game `eval` command is restricted. Only characters
> owned by an **admin** account, or characters wearing an object with
> both the `hat` and `wizard` keywords (a "wizard hat"), may use it.
> 
> 

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
<a id="stop-the-server"></a>

### Stop the Server

In the `SBCL` `REPL`:

```lisp
(apeiron.server:stop-mud-server)
```
This:
1. Sets `*server-running*` to `NIL`
2. Closes the server socket
3. Waits for acceptance thread to exit
4. Disconnects all characters

<a id="x-28APEIRON-DOCS-3A-40ARCHITECTURE-2040ANTS-DOC-2FLOCATIVES-3ASECTION-29"></a>

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
Core is the shared foundation. Worlds and persistence build on it
independently (no dependency between them). Telnet is standalone.
The server layer wires everything together.

<a id="key-design-principles"></a>

### Key Design Principles

1. **Persistent Objects** — game objects are persisted and changes are
   logged to enable recovery (using `BKNR`.Datastore).
2. **All power to the user** — you can eval Lisp code directly within
   the game (could/should be restricted to admins in the future).
3. **Hot Reloading** — no need to ever shut the server down for
   maintenance (`WIP`).

<a id="x-28APEIRON-DOCS-3A-40PROTOCOLS-2040ANTS-DOC-2FLOCATIVES-3ASECTION-29"></a>

## Protocols

* **Telnet (`RFC` 854)** — network protocol for player connections, with
  option negotiation, line editing and echo control
  (see `apeiron/telnet`).
* **`MSSP`** — `MUD` Server Status Protocol: advertises server details
  (name, players, game type, ...) to directory services.
* **`TLS`** — secure transport for telnet connections (via `cl+ssl`).
* **`ANSI` `SGR` colors** — colour output for the client (toggle with
  `toggle-colors`).

<a id="x-28APEIRON-DOCS-3A-40COMMAND-REFERENCE-2040ANTS-DOC-2FLOCATIVES-3ASECTION-29"></a>

## Command Reference

| Command | Usage | Description |
| --- | --- | --- |
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
| `quit` | `quit` | Disconnect |

<a id="documentation"></a>

## Documentation

* Full manual (generated from the source with `40ANTS-DOC`):
  https://sovelten.github.io/apeiron-mud/
* Tutorial: create a secret room —
  [docs/tutorial-secret-room.md][668c]
* Tutorial: Wordle puzzle game —
  [docs/tutorial-wordle.md][954d]
* `MCP` server (`LLM` integration):
  [mcp/README.md][7e6e]


[b83b]: https://github.com/sovelten/apeiron-mud/actions/workflows/test.yml
[668c]: https://github.com/sovelten/apeiron-mud/blob/main/docs/tutorial-secret-room.md
[954d]: https://github.com/sovelten/apeiron-mud/blob/main/docs/tutorial-wordle.md
[7e6e]: https://github.com/sovelten/apeiron-mud/blob/main/mcp/README.md

* * *
###### [generated by [40ANTS-DOC](https://40ants.com/doc/)]
