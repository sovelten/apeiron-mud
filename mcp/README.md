# apeiron-mcp — MCP Server for the Apeiron MUD

An [MCP (Model Context Protocol)](https://spec.modelcontextprotocol.io/) server
that lets an LLM connect to a running [Apeiron MUD](../) as a player character
and interact through the same telnet interface a human player uses.

The LLM can issue any MUD command (`look`, `go`, `say`, `examine`, `attack`,
`inventory`, …) and — crucially — run arbitrary Common Lisp code in the running
game world via the MUD's built-in `eval` command.

```
┌──────────┐   JSON-RPC 2.0    ┌──────────────┐   RFC 854 telnet    ┌───────────┐
│ LLM host │ ◄──────────────► │  apeiron-mcp  │ ◄────────────────► │ Apeiron   │
│ (Claude, │     over stdio    │  (this repo)  │   port 8888/tcp   │ MUD       │
│  etc.)   │                   └──────────────┘                    └───────────┘
└──────────┘
```

## Tools

The server exposes five tools to the LLM:

| Tool             | Description                                                  |
|------------------|--------------------------------------------------------------|
| `mud-connect`    | Connect to a MUD server as a player character                |
| `mud-send`       | Send any MUD command (`look`, `go north`, `say hello`, …)    |
| `mud-eval`       | Execute arbitrary Common Lisp code in the game world          |
| `mud-disconnect` | Disconnect gracefully from the MUD                            |
| `mud-status`     | Check current connection state                                |

### mud-eval — the power tool

`mud-eval` sends a Lisp expression to the MUD's built-in `eval` command.  The
code runs in the `APEIRON.EVAL` package with three convenience functions bound:

| Binding    | Value                                          |
|------------|------------------------------------------------|
| `(me)`     | Your player character (a `mud-character`)      |
| `(here)`   | The room you're standing in (a `mud-room`)     |
| `(world)`  | The `mud-world` instance                       |

Useful accessors you can call on these objects:

```lisp
(object-name obj)       ;; → string
(object-id obj)         ;; → integer
(object-location obj)   ;; → room (for characters/objects)
(room-exits room)       ;; → list of direction keywords
(contents obj)          ;; → list of contained objects
(character-hp char)     ;; → player health
```

Examples:

```lisp
;; Where am I?
(object-name (here))

;; What's around me?
(mapcar #'object-name (contents (here)))

;; Who else is online?
(alexandria:hash-table-values (players (world)))

;; Teleport!
(setf (object-location (me)) some-other-room)
```

## Quick Start

### Prerequisites

- **SBCL** 2.0+ (Steel Bank Common Lisp)
- **Quicklisp** (Common Lisp package manager)
- A running Apeiron MUD server (see [the main README](../README.md#quick-start))

### Starting the MCP server

**HTTP mode (recommended):**

```bash
sbcl --script mcp/run-mcp.lisp --http
```

The server listens on `127.0.0.1:3001/mcp`.  This is a persistent process —
start it once and leave it running.  Your MCP client connects via HTTP.

**Stdio mode (subprocess):**

```bash
sbcl --script mcp/run-mcp.lisp
```

The server reads newline-delimited JSON-RPC 2.0 requests from **stdin** and
writes responses to **stdout**.  The MCP client launches and manages the
process lifecycle.

### Registering with an MCP client

#### ECA (Editor Code Assistant)

Add to `~/.config/eca/config.json`:

```json
{
  "mcpServers": {
    "cl-mcp": {"url": "http://127.0.0.1:3000/mcp"},
    "apeiron-mud": {"url": "http://127.0.0.1:3001/mcp"}
  }
}
```

Then start the HTTP server:

```bash
sbcl --script mcp/run-mcp.lisp --http
```

The server listens on `127.0.0.1:3001` and ECA connects to it via the Streamable
HTTP transport — same pattern as the bundled `cl-mcp` server on port 3000.

#### Claude Desktop / Claude Code

Add to your Claude configuration (`~/.claude/claude_desktop_config.json` or
`~/.claude.json`):

```json
{
  "mcpServers": {
    "apeiron-mud": {
      "command": "sbcl",
      "args": [
        "--noinform", "--non-interactive",
        "--eval", "(require :asdf)",
        "--eval", "(asdf:load-asd #P\"/home/YOU/apeiron-mud/mcp/apeiron-mcp.asd\")",
        "--eval", "(asdf:load-system :apeiron-mcp)",
        "--eval", "(apeiron-mcp/src/package:main)"
      ]
    }
  }
}
```

Replace `/home/YOU/apeiron-mud` with the absolute path to your clone.

#### Continue (VS Code / JetBrains)

In `~/.continue/config.json`:

```json
{
  "experimental": {
    "mcpServers": {
      "apeiron-mud": {
        "command": "sbcl",
        "args": [
          "--noinform", "--non-interactive",
          "--eval", "(require :asdf)",
          "--eval", "(asdf:load-asd #P\"/home/YOU/apeiron-mud/mcp/apeiron-mcp.asd\")",
          "--eval", "(asdf:load-system :apeiron-mcp)",
          "--eval", "(apeiron-mcp/src/package:main)"
        ]
      }
    }
  }
}
```

#### Generic MCP client

Any client that speaks MCP can launch `apeiron-mcp` as a subprocess.  The
command is:

```
sbcl --noinform --non-interactive \
     --eval "(require :asdf)" \
     --eval "(asdf:load-asd #P\"/path/to/apeiron-mud/mcp/apeiron-mcp.asd\")" \
     --eval "(asdf:load-system :apeiron-mcp)" \
     --eval "(apeiron-mcp/src/package:main)"
```

### First session

Once the MCP server is registered with your client, you can start a conversation
like this:

> Connect to the MUD on localhost:8888 as the character "Gandalf".  Then look
> around, explore the starting room, and tell me what you see.

The LLM will call `mud-connect` to log in, then use `mud-send` to issue
commands and `mud-eval` to inspect the world programmatically.

## Architecture

```
mcp/src/
├── package.lisp      Package definition & shared state (*mud-connection*)
├── mud-client.lisp   Telnet client — connect, send commands, read responses
├── tools.lisp        MCP tool registry (descriptors + handlers)
└── server.lisp       JSON-RPC 2.0 / MCP protocol over stdio

mcp/tests/
├── test-package.lisp Test suite & run helper
└── test-mcp.lisp     Unit tests (ANSI, JSON-RPC) + integration tests
```

The server is intentionally small (~500 lines of Common Lisp).  It has only
three dependencies:

| Dependency        | Purpose                          |
|-------------------|----------------------------------|
| `apeiron/telnet`  | RFC 854 telnet client (shared with the MUD) |
| `usocket`         | TCP socket I/O                   |
| `yason`           | JSON parsing / serialisation     |

It does **not** depend on `apeiron/core` — the MCP server is a thin pipe
between the LLM and the telnet interface.  It has no knowledge of MUD internals
beyond what the `mud-eval` tool passes through to the game world.

## How It Works

### Connection flow

1. LLM calls `mud-connect(host, port, name)`.
2. `apeiron-mcp` opens a TCP socket to the MUD, performs RFC 854 telnet option
   negotiation (EOR, Suppress Go Ahead, NAWS, Terminal Type), and reads the
   MUD's name prompt.
3. The player name is sent, and the welcome message + first `> ` prompt are
   read.
4. The connection is stored in `*mud-connection*` for subsequent commands.

### Command flow

1. LLM calls `mud-send(command)`.
2. `apeiron-mcp` writes the command line to the telnet socket (with CR LF).
3. It reads all output lines until the server sends the `> ` prompt — which
   is terminated with an RFC 885 EOR (End of Record) marker rather than CR LF.
4. Output is returned with ANSI escape codes stripped.

### Prompt detection

The MUD sends the prompt `> ` followed by `IAC SB EOR IAC SE` — **no CR LF**.
Because `telnet-read-line` relies on CR LF to delimit lines, it consumes the
`> ` characters internally and then times out waiting for a line terminator.
`apeiron-mcp` treats this timeout as the end-of-output signal: when at least
one line has been received before the timeout, the output is returned
successfully.

## Building a Standalone Binary

```lisp
(asdf:load-system :apeiron-mcp)
(asdf:make :apeiron-mcp)
```

This produces `apeiron-mcp` in the project root, which can be launched
directly:

```bash
./apeiron-mcp
```

## Running Tests

```lisp
(require :asdf)
(asdf:load-asd #P"/path/to/apeiron-mud/mcp/apeiron-mcp-test.asd")
(asdf:test-system :apeiron-mcp-test)
```

Or from the command line:

```bash
sbcl --non-interactive \
     --eval "(require :asdf)" \
     --eval "(asdf:load-asd #P\"$PWD/mcp/apeiron-mcp-test.asd\")" \
     --eval "(asdf:test-system :apeiron-mcp-test)"
```

The test suite covers:

- **ANSI escape stripping** — SGR colors, cursor movement, OSC sequences, plain
  text preservation.
- **JSON-RPC protocol** — initialize handshake, `tools/list`, `tools/call`,
  `ping`, notifications, parse errors, unknown methods.
- **Integration** — full connect → command → disconnect cycles against a
  running MUD server (started and stopped automatically per test).

## MUD Commands Reference

The 15 commands available in the Apeiron MUD (usable via `mud-send`):

| Command           | Usage                     | Description                        |
|-------------------|---------------------------|------------------------------------|
| `look`            | `look`                    | Describe current room              |
| `go`              | `go <direction>`          | Move in a cardinal direction       |
| `exits`           | `exits`                   | List available exits               |
| `examine`         | `examine <name>`          | Examine an NPC or object           |
| `attack`          | `attack <name>`           | Attack an NPC in the room          |
| `status`          | `status`                  | Show your HP (colour-coded)        |
| `answer`          | `answer <text>`           | Answer a challenge/riddle          |
| `say`             | `say <message>`           | Speak to players in the same room  |
| `shout`           | `shout <message>`         | Broadcast to all players           |
| `read`            | `read`                    | Read the guestbook                 |
| `write`           | `write`                   | Write in the guestbook             |
| `inventory`       | `inventory`               | List carried items                 |
| `help`            | `help`                    | List all commands                  |
| `toggle-colors`   | `toggle-colors`           | Enable/disable ANSI colours        |
| `quit`            | `quit`                    | Disconnect from the MUD            |
| `eval`            | `eval <lisp-expression>`  | Execute Lisp in the game world     |

## Design Decisions

### Why Common Lisp?

The MUD itself is written in Common Lisp.  Building the MCP server in the same
language means:

- **Zero new toolchain** — SBCL + Quicklisp is already the project's runtime.
- **Shared telnet library** — `apeiron/telnet` handles RFC 854 byte-level I/O
  for both the MUD server and the MCP client, avoiding a second telnet
  implementation.
- **Single-language debugging** — no context-switching between Python and CL
  when tracing an issue that spans the MCP ↔ MUD boundary.

### Why remote telnet (not in-process)?

The MCP server connects to the MUD over TCP, just like a human player's telnet
client.  This keeps the two processes decoupled:

- The MUD can run on a different machine.
- You can restart the MCP server without touching the MUD.
- The MCP server has no access to MUD internals except what the `eval` command
  explicitly exposes (defence in depth).
