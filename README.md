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
(`CID`) — a hash of its code — computed by the `cl-cm` library. This is the
Unison idea applied to the `MUD`'s scripting: a verb is addressed by *what
it is*, not by where it is stored or what it is called.

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
(defparameter *verbs* (apeiron.verbs:make-verb-registry))

(apeiron.verbs:define-verb *verbs* greet (who)
  "Greet WHO."
  (format nil "Hello, ~A!" who))

(apeiron.verbs:define-verb *verbs* greet-twice (who)
  (greet (greet who)))

(apeiron.verbs:call-verb *verbs* 'greet-twice "world")
;; => "Hello, Hello, world!"
```
Because `greet-twice` calls `greet`, its `CID` depends on `greet`'s: editing
`greet` gives `greet-twice` a new `CID` too, without touching its source. A
compiled verb keeps reaching the version it was compiled against, so
redefining `greet` under the same name does not change what an already
compiled `greet-twice` calls; re-register the caller (or call a freshly
compiled verb) to move to the new version.

<a id="inspecting-the-registry"></a>

### Inspecting the registry

* `VERB-CID` — the `CID` a name currently resolves to.
* `FIND-VERB` / `VERB-SOURCE` / `VERB-DOCSTRING` — the stored definition.
* `VERB-HISTORY` — every `CID` a name has been bound to, newest first.
* `VERB-REFERENCES` — the resolved (`NAME` . `CID`) references of a verb.
* `VERB-REFERRERS` — the names whose current definition references a `CID`.
* `VERB-UNRESOLVED-REFERENCES` — free functions that are not registered
  verbs (they are called as ordinary functions at run time).

`DEFINE-VERB` / `REGISTER-VERB` add or replace a verb by name; `CALL-VERB` runs
one. Registering identical code under two names stores it once and points
both names at the same definition.

<a id="verbs-on-objects"></a>

### Verbs on objects

An object's `VERBS` slot (see the World section) is an immutable `FSET` map
from a verb name to a `CID`; the code itself lives once in the registry. The
per-object `API` is `OBJECT-DEFINE-VERB`! (register a verb and bind it on an
object), `OBJECT-BIND-VERB`! (bind an already-registered `CID` — to share a
definition between objects, or to pin one object to a version), `OBJECT-VERB`
/ `OBJECT-VERB-CID` / `OBJECT-VERB-NAMES` (inspect) and `OBJECT-CALL-VERB` (run).
Because only the `CID` is stored on the object, a verb binding is an ordinary
slot write that `BKNR` records and persists.

<a id="persistence"></a>

### Persistence

The registry is transient (it caches compiled functions); a world keeps it
in its `WORLD-VERB-REGISTRY` slot, created on first use by
`ENSURE-VERB-REGISTRY`. `SAVE-VERB-REGISTRY`! serializes it as plain data
with `VERB-REGISTRY`->`MAP` and stores the result in the world's `CONFIG` map
— an ordinary slot write that `BKNR` records and persists; `LOAD-VERB-REGISTRY`!
rebuilds it from there with `MAP`->`VERB-REGISTRY`, restoring the `CID`s verbatim
without re-hashing, so object verb bindings keep resolving after a restart.

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

### [macro](54ce) `apeiron.verbs:define-verb` registry name lambda-list &body body

Define the verb `NAME` in `REGISTRY` with `LAMBDA-LIST` and `BODY`.
Expands to [`register-verb`][bf76]; see it for the docstring convention and how
references are resolved.

<a id="x-28APEIRON-2EVERBS-3AREGISTER-VERB-20FUNCTION-29"></a>

### [function](aed8) `apeiron.verbs:register-verb` registry name lambda-list body &key strict

Define (or redefine) the verb `NAME` in `REGISTRY` and return its
[`verb-definition`][ca81].

`LAMBDA-LIST` and `BODY` are the verb's parameters and forms; `BODY` may begin
with a docstring (`DEFUN` convention), which is reported by [`verb-docstring`][4e4f].
The whole body — docstring included — is content, so it takes part in the
`CID`.  The verb's `CID` is computed with `CL-CM` after resolving every free
function reference to the `CID` currently bound to that name in `REGISTRY`, so
a reference is to a *version*, not to a name.

If a verb with the same `CID` already exists, `REGISTRY` reuses that definition
(deduplication) and merely points `NAME` at it.  When `STRICT` is true, an
error is signalled if any free function reference could not be resolved to
a registered verb.

<a id="x-28APEIRON-2EVERBS-3ACALL-VERB-20FUNCTION-29"></a>

### [function](b807) `apeiron.verbs:call-verb` registry name-or-cid &rest arguments

Call the verb addressed by `NAME-OR-CID` in `REGISTRY` with `ARGUMENTS`.
Returns whatever the verb returns (including multiple values).

<a id="x-28APEIRON-2EVERBS-3AVERB-CID-20FUNCTION-29"></a>

### [function](c145) `apeiron.verbs:verb-cid` registry name-or-cid

`CID` addressed by `NAME-OR-CID`, or `NIL`.

<a id="x-28APEIRON-2EVERBS-3AVERB-HISTORY-20FUNCTION-29"></a>

### [function](dddb) `apeiron.verbs:verb-history` registry name

List of `CID`s `NAME` has been bound to in `REGISTRY`, newest first.

<a id="x-28APEIRON-2EVERBS-3AVERB-REFERENCES-20FUNCTION-29"></a>

### [function](82bf) `apeiron.verbs:verb-references` registry name-or-cid

Alist (`SYMBOL` . `CID`) of the resolved references of `NAME-OR-CID`.

<a id="x-28APEIRON-2EVERBS-3AVERB-REFERRERS-20FUNCTION-29"></a>

### [function](ff4c) `apeiron.verbs:verb-referrers` registry cid-or-definition

Names whose current definition references `CID-OR-DEFINITION`.
`CID-OR-DEFINITION` may be a `CID` string, a [`verb-definition`][ca81], or a verb `NAME`
(a symbol, resolved through the name index).  The answer is based on the
`CID`, so it is naming-independent: renaming a verb does not change it.

<a id="x-28APEIRON-2EVERBS-3AVERB-UNRESOLVED-REFERENCES-20FUNCTION-29"></a>

### [function](885f) `apeiron.verbs:verb-unresolved-references` registry name-or-cid

Free function symbols of `NAME-OR-CID` that were not resolved to a verb.

<a id="x-28APEIRON-2EVERBS-3AFIND-VERB-20FUNCTION-29"></a>

### [function](6f1b) `apeiron.verbs:find-verb` registry name-or-cid

Return the [`verb-definition`][ca81] named or addressed by `NAME-OR-CID`, or `NIL`.
A string is treated as a `CID`; a symbol is resolved through the name index.

<a id="x-28APEIRON-2EVERBS-3AVERB-SOURCE-20FUNCTION-29"></a>

### [function](7f6e) `apeiron.verbs:verb-source` registry name-or-cid

Source form of the verb addressed by `NAME-OR-CID`.

<a id="x-28APEIRON-2EVERBS-3AVERB-DOCSTRING-20FUNCTION-29"></a>

### [function](0fa5) `apeiron.verbs:verb-docstring` registry name-or-cid

Docstring of the verb addressed by `NAME-OR-CID`.

<a id="x-28APEIRON-2EVERBS-3AENSURE-VERB-REGISTRY-20FUNCTION-29"></a>

### [function](b3c5) `apeiron.verbs:ensure-verb-registry` world

Return `WORLD`'s verb registry, creating an empty one on first use.
`WORLD`'s registry lives in its transient `world-verb-registry` ([`1`][0e7c] [`2`][e12c] [`3`][c421]) slot.

<a id="x-28APEIRON-2EVERBS-3AVERB-REGISTRY--3EMAP-20FUNCTION-29"></a>

### [function](afaa) `apeiron.verbs:verb-registry->map` registry

Return `REGISTRY` as an immutable `FSET` map of plain data.

The map has keys `:VERB-REGISTRY-FORMAT`, `:DEFINITIONS` (a list of serialized
definitions), `:NAMES` (a list of (printed-name . cid)) and `:HISTORY` (a list
of (printed-name . cid-list)).  It contains no class instances and no
symbols, so it can be persisted directly; `MAP`->[`verb-registry`][8830] restores it.

<a id="x-28APEIRON-2EVERBS-3AMAP--3EVERB-REGISTRY-20FUNCTION-29"></a>

### [function](feef) `apeiron.verbs:map->verb-registry` map

Rebuild a verb registry from the plain data `MAP` produced by
[`verb-registry`][8830]->`MAP`.  `CID`s, names and history are restored verbatim, so the
result addresses exactly the same definitions.

<a id="x-28APEIRON-2EVERBS-3ASAVE-VERB-REGISTRY-21-20FUNCTION-29"></a>

### [function](f469) `apeiron.verbs:save-verb-registry!` world &key (key \*verb-registry-config-key\*)

Serialize `WORLD`'s verb registry into `WORLD`'s `CONFIG` map so the datastore
stores it.  Returns the serialized map.

Object verb bindings are name -> `CID`; the code those `CID`s name lives only in
the registry, so persisting the registry is what makes an object's verbs
survive a restart.  Restore it with `LOAD-VERB-REGISTRY`!.

<a id="x-28APEIRON-2EVERBS-3ALOAD-VERB-REGISTRY-21-20FUNCTION-29"></a>

### [function](aa6c) `apeiron.verbs:load-verb-registry!` world &key (key \*verb-registry-config-key\*)

Rebuild `WORLD`'s verb registry from the serialized map stored in its `CONFIG`
map under `KEY`, and install it in `WORLD`'s `world-verb-registry` ([`1`][0e7c] [`2`][e12c] [`3`][c421]) slot.  `CID`s are
restored verbatim, without re-hashing, so object verb bindings keep
resolving.  Returns the registry, or `NIL` when nothing is stored.

<a id="x-28APEIRON-2EVERBS-3AOBJECT-DEFINE-VERB-21-20-2840ANTS-DOC-2FLOCATIVES-3AMACRO-29-29"></a>

### [macro](303b) `apeiron.verbs:object-define-verb!` registry object name lambda-list &body body

Register a verb `NAME` (with `LAMBDA-LIST` and `BODY`) in `REGISTRY` and bind it
on `OBJECT`.  Returns the [`verb-definition`][ca81].  This is how an object gains its own
way of answering a command: the definition is content-addressed and shared,
`OBJECT` just points at it.

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

### [function](7b56) `apeiron.verbs:object-bind-verb!` object name cid

Bind `NAME` on `OBJECT` to the already-registered `CID`.  Returns `CID`.
Use this to share a definition between objects, or to pin one object to a
specific version while another object moves on.

<a id="x-28APEIRON-2EVERBS-3AOBJECT-VERB-20FUNCTION-29"></a>

### [function](eb21) `apeiron.verbs:object-verb` registry object name

Return the [`verb-definition`][ca81] `OBJECT` binds to `NAME` in `REGISTRY`, or `NIL`.

<a id="x-28APEIRON-2EVERBS-3AOBJECT-CALL-VERB-20FUNCTION-29"></a>

### [function](c152) `apeiron.verbs:object-call-verb` registry object name &rest arguments

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
[b807]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/compile.lisp#L63
[303b]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/integration.lisp#L11
[7b56]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/integration.lisp#L31
[eb21]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/integration.lisp#L37
[c152]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/integration.lisp#L42
[f469]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/integration.lisp#L65
[aa6c]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/integration.lisp#L77
[dddb]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L119
[6f1b]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L141
[c145]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L149
[7f6e]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L154
[0fa5]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L158
[82bf]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L162
[885f]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L166
[ff4c]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L170
[aed8]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L232
[54ce]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L275
[b3c5]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/registry.lisp#L93
[afaa]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/serialize.lisp#L44
[feef]: https://github.com/sovelten/apeiron-mud/blob/8fe1585cd96403d1282ed681462c72110287e6f9/src/verbs/serialize.lisp#L69
[668c]: https://github.com/sovelten/apeiron-mud/blob/main/docs/tutorial-secret-room.md
[954d]: https://github.com/sovelten/apeiron-mud/blob/main/docs/tutorial-wordle.md
[7e6e]: https://github.com/sovelten/apeiron-mud/blob/main/mcp/README.md
[0e7c]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2ECORE-3AWORLD-VERB-REGISTRY-20-2840ANTS-DOC-2FLOCATIVES-3AACCESSOR-20APEIRON-2ECORE-3AMUD-WORLD-29-29
[e12c]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2ECORE-3AWORLD-VERB-REGISTRY-20-2840ANTS-DOC-2FLOCATIVES-3AREADER-20APEIRON-2ECORE-3AMUD-WORLD-29-29
[c421]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2ECORE-3AWORLD-VERB-REGISTRY-20GENERIC-FUNCTION-29
[11fb]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3ADEFINE-VERB-20-2840ANTS-DOC-2FLOCATIVES-3AMACRO-29-29
[bf76]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3AREGISTER-VERB-20FUNCTION-29
[ca81]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3AVERB-DEFINITION-20CLASS-29
[4e4f]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3AVERB-DOCSTRING-20FUNCTION-29
[8830]: https://sovelten.github.io/apeiron-mud/#x-28APEIRON-2EVERBS-3AVERB-REGISTRY-20CLASS-29

* * *
###### [generated by [40ANTS-DOC](https://40ants.com/doc/)]
