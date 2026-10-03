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
  - **Hot reloading** — reload changed code into a running server without restarting (`reload-apeiron`, `safe-update`)
  - **Room system** — navigable rooms with directional exits (north, south, east, west)
  - **Player chat** — `say` command for in-room communication
  - **Inventory system** — foundation for item management
  - **Command system** — 17 built-in commands, easy to add more

  ### Planned

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
  - **GMCP** — Generic Mud Communication Protocol (telnet option 201):
    structured out-of-band client data.  The server pushes character
    stats as `Char.Vitals` (hp/maxhp) and `Char.Stats` (str/sta/int).
    The protocol engine lives in `apeiron/telnet` and is decoupled from
    the game — the mapping from characters to GMCP packages is done in
    the server bridge (`session-sync-character`).
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

(defsection @persistence (:title "Persistence")
  """The game world and every object in it live in a BKNR datastore.
  Transient game objects are converted to *persistent* counterparts
  (BKNR store-objects) whose changes are journaled, so everything
  survives restarts and crashes.

  ### Declarative persistent classes

  Persistent classes are declared as *data* in
  `src/persistence/registry.lisp`: a serapeum dict,
  `*PERSISTENT-CLASS-REGISTRY*`, maps each transient game class to an
  options dict.

  ```lisp
  (defparameter *persistent-class-registry*
    (dict
     'mud-object        (dict)
     'mud-room          (dict :transient-slots '(contents))
     'mud-character     (dict :transient-slots '(session))
     'mud-guestbook     (dict :transient-slots '(entries))
     'mud-world         (dict :transient-slots '(characters objects rooms areas))))
  ```

  `DEFINE-PERSISTENT-CLASSES` reads the registry and defines the
  wrapping `PERSISTENT-*` classes:
  - **name** — `PERSISTENT-<name>` by default (`MUD-ROOM` →
    `PERSISTENT-ROOM`), overridable with `:persistent-name`;
  - **superclasses** — the transient class plus `PERSISTENT-OBJECT`
    when it is a `MUD-OBJECT` subtype, so every game object shares the
    same persistence behavior; overridable with `:superclasses`;
  - **transient slots** — `:transient-slots` lists the slots inherited
    from the transient class that must NOT be stored, for example a
    character's live `session` or a world's in-memory indices.

  Adding a new persistent class is a one-line registry entry — no
  class definitions to hand-write.

  ### Materialization and restore

  `MATERIALIZE-OBJECT` converts a transient object into its persistent
  counterpart in place (preserving identity and cross-references).
  `WORLD-RESTORE-OR-INITIALIZE` restores the stored world on startup —
  or materializes a fresh one when no store exists yet.

  ### Updating a running server

  `SAFE-UPDATE` reloads changed code into a live image without a
  restart.  It snapshots the datastore first (a rollback baseline),
  reloads the changed systems via `RELOAD-APEIRON`, and takes a second
  snapshot only when the persistent class schemas actually changed —
  the situation BKNR warns about, where the new schema must be
  persisted.  If no class changed, the redundant second snapshot is
  skipped.  See @DEPLOYMENT."""
  (apeiron.persistence::@data-migrations section))

(defsection @verbs (:title "Content-addressed verbs")
  """A *verb* is a named function whose identity is a content identifier
  (CID) — a hash of its code — computed by the `cl-cm` library. This is the
  Unison idea applied to the MUD's scripting: a verb is addressed by *what
  it is*, not by where it is stored or what it is called.

  ### How a verb's CID is computed

  A verb is defined by a lambda list and a body. `cl-cm` alpha-renames the
  code, so the names of a verb's own bound variables do not affect the CID,
  and replaces every *free* reference to another verb with that verb's CID.
  The result is *recursive content addressing*:

  - renaming a verb changes no CID — a reference is to a version, not to a
    name;
  - editing a verb's body gives it a new CID, and gives a new CID to every
    verb that calls it, because the caller's CID depends on the callee's;
  - identical verbs are stored once, however they are named.

  A leading string literal in the body is the verb's docstring (the DEFUN
  convention) and, being content, it takes part in the CID.

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

  Because `greet-twice` calls `greet`, its CID depends on `greet`'s: editing
  `greet` gives `greet-twice` a new CID too, without touching its source. A
  compiled verb keeps reaching the version it was compiled against, so
  redefining `greet` under the same name does not change what an already
  compiled `greet-twice` calls; re-register the caller (or call a freshly
  compiled verb) to move to the new version.

  ### Inspecting the registry

  - VERB-CID — the CID a name currently resolves to.
  - FIND-VERB / VERB-SOURCE / VERB-DOCSTRING — the stored definition.
  - VERB-HISTORY — every CID a name has been bound to, newest first.
  - VERB-REFERENCES — the resolved (NAME . CID) references of a verb.
  - VERB-REFERRERS — the names whose current definition references a CID.
  - VERB-UNRESOLVED-REFERENCES — free functions that are not registered
    verbs (they are called as ordinary functions at run time).

  DEFINE-VERB / REGISTER-VERB add or replace a verb by name; CALL-VERB runs
  one. Registering identical code under two names stores it once and points
  both names at the same definition.

  ### Verbs on objects

  An object's `VERBS` slot (see the World section) is an immutable FSET map
  from a verb name to a CID; the code itself lives once in the registry. The
  per-object API is OBJECT-DEFINE-VERB! (register a verb and bind it on an
  object), OBJECT-BIND-VERB! (bind an already-registered CID — to share a
  definition between objects, or to pin one object to a version), OBJECT-VERB
  / OBJECT-VERB-CID / OBJECT-VERB-NAMES (inspect) and OBJECT-CALL-VERB (run).
  Because only the CID is stored on the object, a verb binding is an ordinary
  slot write that BKNR records and persists.

  ### Persistence

  The registry is transient (it caches compiled functions); a world keeps it
  in its `WORLD-VERB-REGISTRY` slot, created on first use by
  `ENSURE-VERB-REGISTRY`. SAVE-VERB-REGISTRY! serializes it as plain data
  with VERB-REGISTRY->MAP and stores the result in the world's `CONFIG` map
  — an ordinary slot write that BKNR records and persists; LOAD-VERB-REGISTRY!
  rebuilds it from there with MAP->VERB-REGISTRY, restoring the CIDs verbatim
  without re-hashing, so object verb bindings keep resolving after a restart.

  ### Limitations

  - A referenced name must already be bound when the referrer is registered:
    *forward references* and *mutual recursion* between two brand-new verbs
    are not supported. A self-recursive verb either uses `labels` inside its
    body or refers to the previously registered version of itself.
  - Free functions that are not registered verbs are resolved by name at run
    time and are not content-addressed; REGISTER-VERB with `:STRICT` rejects
    them.
  - A verb may be named by a symbol of a locked package (such as `GET` or
    `REMOVE` in COMMON-LISP); the compilation step lifts the package lock for
    exactly the referenced names, so such a reference can still be pinned by
    CID."""
  (apeiron.verbs:define-verb macro)
  (apeiron.verbs:register-verb function)
  (apeiron.verbs:call-verb function)
  (apeiron.verbs:verb-cid function)
  (apeiron.verbs:verb-history function)
  (apeiron.verbs:verb-references function)
  (apeiron.verbs:verb-referrers function)
  (apeiron.verbs:verb-unresolved-references function)
  (apeiron.verbs:find-verb function)
  (apeiron.verbs:verb-source function)
  (apeiron.verbs:verb-docstring function)
  (apeiron.verbs:ensure-verb-registry function)
  (apeiron.verbs:verb-registry->map function)
  (apeiron.verbs:map->verb-registry function)
  (apeiron.verbs:save-verb-registry! function)
  (apeiron.verbs:load-verb-registry! function)
  (apeiron.verbs:object-define-verb! macro)
  (apeiron.verbs:object-bind-verb! function)
  (apeiron.verbs:object-verb function)
  (apeiron.verbs:object-call-verb function)
  (apeiron.core:object-verbs generic-function)
  (apeiron.core:world-verb-registry generic-function))

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

  ### Updating a Running Server

  Pull the latest code and reload it into the running image without a
  restart:

  ```lisp
  (apeiron.persistence:safe-update)
  ```

  `SAFE-UPDATE` snapshots the datastore first (a rollback baseline),
  reloads the changed APEIRON systems via `reload-apeiron`, then takes a
  second snapshot only when persistent class definitions changed — so a
  new class schema is persisted.  If nothing changed, the second snapshot
  is skipped.

  After a reload, `SAFE-UPDATE` also runs any pending *data migrations*
  registered in the persistence module (see
  `run-data-migrations`).  Migrations upgrade datastores written by older
  code — e.g. when a persistent slot was renamed — and are data-driven:
  adding a new migration never requires editing `safe-update` itself.

  Because a migration ships in the same code load that an already-running
  old `safe-update` cannot know about, migrations are also run
  automatically from `world-restore-or-initialize` whenever a datastore
  is opened by the current code.  Restarting the server with the new code
  is therefore always sufficient to migrate an old datastore — no manual
  step is needed, and you never depend on an old `safe-update` knowing
  about a brand-new migration.

  For quick development reloads from inside the game, use the eval
  command:

  ```
  eval (reload-apeiron)
  ```

  **Note on hot reloads and runtime configuration:** server settings such
  as `*server-ssl-certificate*`, `*server-ssl-key*`, `*server-port*`, and
  `*server-tls-port*` are declared with `defvar` (not `defparameter`) on
  purpose.  A reload leaves an already-bound configuration variable
  untouched, so the running listeners keep their settings.  If these were
  `defparameter`, every reload would reset them to their defaults — for
  example wiping the TLS certificate from a live server, after which each
  new TLS connection fails the handshake with OpenSSL's opaque
  `no shared cipher` error.

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
  - **serapeum** — utility hash tables (the declarative persistent class registry)
  - **cl-cm** — content-addressable Common Lisp code: alpha-equivalent
    normalisation and content identifiers. Not on Quicklisp; keep it on the
    ASDF source registry (e.g. Quicklisp's `local-projects`). It is the basis
    of the verb registry (see @VERBS).
  - **fiveam** — testing (optional)

  All installed via Quicklisp automatically.""")

(defsection @mcp (:title "MCP Server (LLM Integration)")
  """An [MCP (Model Context Protocol)](https://spec.modelcontextprotocol.io/)
  server is included in `mcp/`. It lets an LLM (Claude, Continue, etc.)
  connect to the MUD as a player character, issue commands, and run Lisp
  code in the game world.

  See [mcp/README.md](https://github.com/sovelten/apeiron-mud/blob/main/mcp/README.md)
  for setup and usage.""")
