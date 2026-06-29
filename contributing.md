# Design Guidelines

This code represents a common-lisp MUD server. If actual code contradicts this document, this document should take precedence, as it represents the designer intention rather than the actual implementation with the shortcuts we had to take along the way.

## Key Features

1. **Persistent Objects** - Game objects are persisted and changes are logged to enable recovery.
2. **All power to the user** - You can eval lisp code directly within the game (could/should be restricted to admins in the future)
3. **Hot Reloading** - No need to ever shut the server down for maintenance (WIP)

## Architecture

These are the main layers of the code base:

```
     apeiron/core
     /     |     \
worlds  persistence  telnet
     \     |     /
        server
           |
       apeiron (meta)
```

Core is the shared foundation. Worlds and persistence build on it independently (no dependency between them). Telnet is standalone. The server layer wires everything together.

### Core - Main world model. Keeps track of world objects and configuration
  * world.lisp
  * etc.

### Persistent World - Deals with persistence storage.

  * persistent-world.lisp
  * store.lisp

We should theoretically be able to load a fully transient world that does not rely on this layer and only lives in RAM. Persistent layer should be able to transform a fully transient world into persistent, keeping track of persisted entities and logging or snapshotting for recovery in case the server is restarted.

### Telnet - Implements telnet RFC 854 (and possibly other additions)

This is the code of the telnet server. It should not depend on any of the other layers. The core layer relies on generic methods that can be implemented by string streams for testing purposes.

### Worlds - One or more constructed worlds build from the fundamental pieces in the core layer

This is the world (or worlds) itself. This is done so that people can use the other modules to build their own worlds.

### Server - Includes network related logic

  * network.lisp (main entry point, server start and thread control)

This connects everything together (telnet, core, persistency, worlds) to build load a particular world in a server.

## Design Best Practices

We value functional programming design, therefore:
* Avoid sharing global mutable state.
* Prefer passing down values as arguments rather than referring to a global variable

### Separation of Concerns

* Aim for code to be generic and extensible.

### Testing

* Unit testing should be about a single data structure/function/object. If you need to mock the network or another side effect, likely you are doing something wrong.
* Integration tests are about testing the whole program behavior. They should either rely on test versions of the generic methods (not implemented as of this moment) or mirror production.
* All integration tests should have initialization and tear down of anything that requires stateful change or network interaction. In other words, tests should be isolated and not affect other tests.
* Integration tests live in test-integration.lisp and the other test files are to be seen as unit.
