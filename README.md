<a id="x-28APEIRON-DOCS-3A-40README-2040ANTS-DOC-2FLOCATIVES-3ASECTION-29"></a>

# Apeiron

Apeiron is a `MUD` server written in Common Lisp, inspired by
Dworkin's Game Driver (`DGD`) and LambdaMoo and using Common Lisp as the scripting language.

[![](https://github.com/sovelten/apeiron-mud/actions/workflows/test.yml/badge.svg)][b83b]

<a id="x-28APEIRON-DOCS-3A-40GETTING-STARTED-2040ANTS-DOC-2FLOCATIVES-3ASECTION-29"></a>

## Getting Started

<a id="prerequisites"></a>

### Prerequisites

* **`SBCL`** 2.0+
* **Quicklisp**
* **cl-cm** — not on Quicklisp. Clone
  https://github.com/sovelten/cl-cm into Quicklisp's `local-projects`

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
> eval (create-object! (world) (new-room :name "Rivendell"))
#<MUD-ROOM Rivendell (ID: 8)>
> eval (connect-rooms! (world) (here) "east" (obj-find "Rivendell") "west")
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
* **`GMCP`** — Generic Mud Communication Protocol (telnet option 201):
  structured out-of-band client data.  The server pushes character
  stats as `Char.Vitals` (hp/maxhp) and `Char.Stats` (str/sta/int).
  The protocol engine lives in `apeiron/telnet` and is decoupled from
  the game — the mapping from characters to `GMCP` packages is done in
  the server bridge (`session-sync-character`).
* **`TLS`** — secure transport for telnet connections (via `cl+ssl`).
* **`ANSI` `SGR` colors** — colour output for the client (toggle with
  `toggle-colors`).

<a id="x-28APEIRON-DOCS-3A-40VERBS-2040ANTS-DOC-2FLOCATIVES-3ASECTION-29"></a>

## Content-addressed verbs

A *verb* is a named function whose identity is a content identifier
(`CID`) — a hash of its code — computed by the `cl-cm` library and stored in
a `cl-cm-db` code database. This is the Unison idea applied to the `MUD`'s
scripting: a verb is addressed by *what it is*, not by where it is stored
or what it is called.

<a id="how-a-verb-s-cid-is-computed"></a>

### How a verb's CID is computed

A verb is defined by a lambda list and a body. `cl-cm` alpha-renames the
code, so the names of a verb's own bound variables do not affect the `CID`,
and replaces every *free* reference to another verb with that verb's `CID`.
The result is *recursive content addressing*:

* renaming a verb changes no `CID` — a reference is to a version, not to a
  name;
* editing a verb's body gives it a new `CID`, and gives a new `CID` to every
  verb that calls it, because the caller's `CID` depends on the callee's;
* identical verbs are stored once, however they are named.

A leading string literal in the body is the verb's docstring (the `DEFUN`
convention) and, being content, it takes part in the `CID`.

<a id="defining-and-calling"></a>

### Defining and calling

```lisp
(defparameter *verbs*
  (cl-cm-db:ensure-database
   (cl-cm-db:make-database :directory #p"data/verbs/" :name "verbs")))

(apeiron.verbs:define-verb *verbs* greet (who)
  "Greet WHO."
  (format nil "Hello, ~A!" who))

(apeiron.verbs:define-verb *verbs* greet-twice (who)
  (greet (greet who)))

(cl-cm-db:call-identity 'greet-twice *verbs* "world")
;; => "Hello, Hello, world!"
```
`DEFINE-VERB` is only sugar: it builds the `(lambda ...)` form and stores
it with `CL-CM-DB:ENSURE-IDENTITY`. Renaming, redefinition, deduplication
and recursive content addressing are the database's behavior.

Because `greet-twice` calls `greet`, its `CID` depends on `greet`'s: editing
`greet` gives `greet-twice` a new `CID` too, without touching its source. A
compiled verb keeps reaching the version it was compiled against, so
redefining `greet` under the same name does not change what an already
compiled `greet-twice` calls; re-register the caller (or call a freshly
compiled verb) to move to the new version.

<a id="inspecting-verbs"></a>

### Inspecting verbs

Inspection is `cl-cm-db`:

* `CL-CM-DB:IDENTITY-CID` — the `CID` a name currently resolves to.
* `CL-CM-DB:DEFINITION-BY-IDENTITY` / `DEFINITION-BY-CID` — the stored
  `CODE-DEFINITION` (source, lambda list, body).
* `CL-CM-DB:IDENTITY-HISTORY` — every `CID` a name has been bound to,
  newest first.
* `CL-CM-DB:CODE-REFERENCES` — the `(NAME . CID)` references a stored
  definition was hashed with.
* `CL-CM-DB:CODE-REFERRERS` — the names whose current definition
  references a `CID`.
* `CL-CM-DB:CODE-FUNCTION` / `CALL-IDENTITY` — the compiled function.
* [`apeiron.verbs:verb-docstring`][4e4f] — the `DEFUN`-style docstring of a
  definition.

`DEFINE-VERB` / `REGISTER-VERB` add or replace a verb by name. Registering
identical code under two names stores it once and points both names at the
same definition.

<a id="verbs-on-objects"></a>

### Verbs on objects

An object's `VERBS` slot (see the World section) is an immutable `FSET` map
from a verb name to a `CID`; the code itself lives once in the registry. The
per-object `API` is `OBJECT-DEFINE-VERB`! (register a verb and bind it on an
object), `OBJECT-BIND-VERB`! (bind an already-registered `CID` — to share a
definition between objects, or to pin one object to a version), `OBJECT-VERB`
(returns the `CL-CM-DB:CODE-DEFINITION`), `OBJECT-VERB-CID` /
`OBJECT-VERB-NAMES` (inspect) and `OBJECT-CALL-VERB` (run). Because only the
`CID` is stored on the object, a verb binding is an ordinary slot write that
`BKNR` records and persists.

<a id="storage"></a>

### Storage

A registry *is* a `cl-cm-db` code database — there is no separate
registry object. The database owns persistence: it keeps an append-only
identity log mapping verb names to `CID`s, and a content-addressed object
store holding each definition's source (identical code is stored once).
Every definition or redefinition is written to that log, which is also
where `CL-CM-DB:IDENTITY-HISTORY` comes from. Open a standalone database
with `CL-CM-DB:MAKE-DATABASE` + `ENSURE-DATABASE` (or `INIT-DATABASE`).

The database also owns the compiled code: it lazily compiles a stored
definition and caches the compiled function by `CID`, wiring each free
reference to the compiled function of the referenced `CID`. Nothing about
compiled code is persisted; it is rebuilt from the stored source on
demand, so an image restart simply recompiles on first call.

A world keeps its database in the transient `WORLD-VERB-REGISTRY` slot,
created on first use by `ENSURE-VERB-REGISTRY`. The database directory is
`DATA/VERBS/` by default, or the world's `:VERB-DIRECTORY` config value,
or the explicit `:DIRECTORY` argument. An object's `VERBS` slot still
stores name -> `CID`, so object bindings survive a restart as ordinary `BKNR`
slot writes, and the `CID`s they name remain addressable in the code store
even after a verb is redefined.

<a id="limitations"></a>

### Limitations

* A referenced name must already be bound when the referrer is registered:
  *forward references* and *mutual recursion* between two brand-new verbs
  are not supported. A self-recursive verb either uses `labels` inside its
  body or refers to the previously registered version of itself.
* Free functions that are not registered verbs are resolved by name at run
  time and are not content-addressed; `REGISTER-VERB` with `:STRICT` rejects
  them.
* A verb may be named by a symbol of a locked package (such as `GET` or
  `REMOVE` in `COMMON-LISP`); the compilation step lifts the package lock for
  exactly the referenced names, so such a reference can still be pinned by
  `CID`.

<a id="x-28APEIRON-2EVERBS-3ADEFINE-VERB-20-2840ANTS-DOC-2FLOCATIVES-3AMACRO-29-29"></a>

### [macro](4c18) `apeiron.verbs:define-verb` registry name lambda-list &body body

Define the verb `NAME` in `REGISTRY` with `LAMBDA-LIST` and `BODY`.
Expands to [`register-verb`][bf76]; see it for the docstring convention and how
references are resolved.

<a id="x-28APEIRON-2EVERBS-3AREGISTER-VERB-20FUNCTION-29"></a>

### [function](fe75) `apeiron.verbs:register-verb` registry name lambda-list body &key strict

Define (or redefine) the verb `NAME` in `REGISTRY` and return its
`CL-CM-DB:CODE-DEFINITION`.

`LAMBDA-LIST` and `BODY` are the verb's parameters and forms; `BODY` may begin
with a docstring (`DEFUN` convention), reported by [`verb-docstring`][4e4f].  The whole
body — docstring included — is content, so it takes part in the `CID`.

`REGISTRY` is a `CL-CM-DB` code database.  The definition is stored with
`CL-CM-DB:ENSURE-IDENTITY`, so a new name gets a `:define' record, an existing
one a`:set' record, and re-storing identical content is a no-op.  When
`STRICT` is true, an error is signalled if any free function reference could
not be resolved to a registered identity.

<a id="x-28APEIRON-2EVERBS-3AVERB-DOCSTRING-20FUNCTION-29"></a>

### [function](1ee4) `apeiron.verbs:verb-docstring` definition

The docstring of `DEFINITION` (a `CL-CM-DB:CODE-DEFINITION`), or `NIL`.
A leading string in the body is a docstring, as in `DEFUN`.  It stays in the
body and therefore takes part in the `CID`: the documentation is content.

<a id="x-28APEIRON-2EVERBS-3AENSURE-VERB-REGISTRY-20FUNCTION-29"></a>

### [function](8102) `apeiron.verbs:ensure-verb-registry` world &key directory

Return `WORLD`'s verb database, opening it on first use.
`WORLD`'s registry lives in its transient `world-verb-registry` ([`1`][0e7c] [`2`][e12c] [`3`][c421]) slot and is a
`CL-CM-DB:CODE-DATABASE`.  The directory is `DIRECTORY` when supplied, else
`WORLD`'s `:VERB-DIRECTORY` config value, else
[`default-verb-database-directory`][ddac].

<a id="x-28APEIRON-2EVERBS-3ADEFAULT-VERB-DATABASE-DIRECTORY-20FUNCTION-29"></a>

### [function](9044) `apeiron.verbs:default-verb-database-directory`

Where a world's verb database lives by default: `DATA`/`VERBS`/.

<a id="x-28APEIRON-2EVERBS-3AOBJECT-DEFINE-VERB-21-20-2840ANTS-DOC-2FLOCATIVES-3AMACRO-29-29"></a>

### [macro](c21e) `apeiron.verbs:object-define-verb!` registry object name lambda-list &body body

Register a verb `NAME` (with `LAMBDA-LIST` and `BODY`) in `REGISTRY` and bind it
on `OBJECT`.  Returns the `CL-CM-DB:CODE-DEFINITION`.  This is how an object
gains its own way of answering a command: the definition is
content-addressed and shared, `OBJECT` just points at it.

`NAME` is a literal symbol, as in [`define-verb`][11fb], and `BODY` may begin with a
docstring.  `REGISTRY` and `OBJECT` are ordinary expressions, each evaluated
once:

```text
(object-define-verb! (ensure-verb-registry world) lamp 'light
  (&optional who)
  "Light the lamp, optionally telling WHO."
  (set-lamp-lit lamp t)
  (when who (tell who "The lamp flickers to life.")))
```
<a id="x-28APEIRON-2EVERBS-3AOBJECT-BIND-VERB-21-20FUNCTION-29"></a>

### [function](b48c) `apeiron.verbs:object-bind-verb!` object name cid

Bind `NAME` on `OBJECT` to the already-registered `CID`.  Returns `CID`.
Use this to share a definition between objects, or to pin one object to a
specific version while another object moves on.

<a id="x-28APEIRON-2EVERBS-3AOBJECT-VERB-20FUNCTION-29"></a>

### [function](0dd3) `apeiron.verbs:object-verb` registry object name

Return the `CL-CM-DB:CODE-DEFINITION` `OBJECT` binds to `NAME` in `REGISTRY`, or `NIL`.

<a id="x-28APEIRON-2EVERBS-3AOBJECT-CALL-VERB-20FUNCTION-29"></a>

### [function](14e7) `apeiron.verbs:object-call-verb` registry object name &rest arguments

Call the verb `OBJECT` binds to `NAME` with `ARGUMENTS`, resolving nested verb
references through `REGISTRY`.  Returns whatever the verb returns.

<a id="x-28APEIRON-2ECORE-3AOBJECT-VERBS-20GENERIC-FUNCTION-29"></a>

### [generic-function] `apeiron.core:object-verbs` object

<a id="x-28APEIRON-2ECORE-3AWORLD-VERB-REGISTRY-20GENERIC-FUNCTION-29"></a>

### [generic-function] `apeiron.core:world-verb-registry` object

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
[c21e]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/integration.lisp#L12
[b48c]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/integration.lisp#L32
[0dd3]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/integration.lisp#L38
[14e7]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/integration.lisp#L43
[1ee4]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/verbs.lisp#L26
[fe75]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/verbs.lisp#L32
[4c18]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/verbs.lisp#L57
[9044]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/verbs.lisp#L67
[8102]: https://github.com/sovelten/apeiron-mud/blob/a1597bfc4bd2c41b0d619b39cb355713ac393f0c/src/verbs/verbs.lisp#L71
[668c]: https://github.com/sovelten/apeiron-mud/blob/main/docs/tutorial-secret-room.md
[954d]: https://github.com/sovelten/apeiron-mud/blob/main/docs/tutorial-wordle.md
[7e6e]: https://github.com/sovelten/apeiron-mud/blob/main/mcp/README.md
[0e7c]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2ECORE-3AWORLD-VERB-REGISTRY-20-2840ANTS-DOC-2FLOCATIVES-3AACCESSOR-20APEIRON-2ECORE-3AMUD-WORLD-29-29
[e12c]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2ECORE-3AWORLD-VERB-REGISTRY-20-2840ANTS-DOC-2FLOCATIVES-3AREADER-20APEIRON-2ECORE-3AMUD-WORLD-29-29
[c421]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2ECORE-3AWORLD-VERB-REGISTRY-20GENERIC-FUNCTION-29
[ddac]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3ADEFAULT-VERB-DATABASE-DIRECTORY-20FUNCTION-29
[11fb]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3ADEFINE-VERB-20-2840ANTS-DOC-2FLOCATIVES-3AMACRO-29-29
[bf76]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3AREGISTER-VERB-20FUNCTION-29
[4e4f]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3AVERB-DOCSTRING-20FUNCTION-29

* * *
###### [generated by [40ANTS-DOC](https://40ants.com/doc/)]
