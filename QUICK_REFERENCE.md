# QUICK REFERENCE CARD

## 🚀 Start the Server (2 minutes)

```bash
# Step 1: Install dependencies (first time only)
./setup.sh

# Step 2: Start the server
sbcl
> (push (uiop:getcwd) asdf:*central-registry*)
> (ql:quickload :mud)
> (mud:start)
```

**IMPORTANT:** The line `(push (uiop:getcwd) asdf:*central-registry*)` tells SBCL where to find mud.asd

## 🎮 Play the MUD

```bash
# In another terminal, connect as a player
telnet localhost 8888

# Commands while playing:
look              # See current room
go north          # Move north (or south, east, west)
exits             # See available exits
inventory         # See what you're carrying
say hello!        # Say something to other players
help              # List all commands
quit              # Disconnect
```

## 🛑 Stop the Server

```lisp
# In the SBCL window where you started it:
> (mud:stop)
```

## 📊 Check Server Status

```lisp
> (mud:status)
# Shows: Players online, rooms in world, server status
```

## 📚 Documentation Files

| Want | Read |
|------|------|
| Getting started | `QUICKSTART.md` |
| Add features | `DEVELOPMENT.md` |
| How it works | `ARCHITECTURE.md` |
| Project overview | `README.md` |
| Navigation | `INDEX.md` |

## 🔧 Common Development Tasks

### Add a New Command

Edit `src/command-handler.lisp` and add:

```lisp
(define-command "wave" (player args)
  (player-send-message player "You wave hello!"))
```

### Create a Room

```lisp
(let ((room (mud:create-room :name "A Forest")))
  (mud:world-add-room room)
  room)
```

### Connect Rooms

```lisp
(mud:room-add-exit room1 "north" room2)
(mud:room-add-exit room2 "south" room1)
```

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| "Cannot find :mud" | Make sure mud.asd is in current dir |
| Port in use | Change port in `src/constants.lisp` |
| Cannot connect | Verify server is running, check firewall |
| Dependency errors | Run `(ql:quickload (list "usocket" "bordeaux-threads"))` |

## 📞 Directory Structure

```
musical-guacamole/
├── src/              # Source code (9 files)
├── tests/            # Test suite (3 files)
├── *.md              # Documentation (8 files)
├── *.sh              # Scripts (setup, testing)
└── mud.asd           # System configuration
```

## ⚡ Key Files

- **object.lisp** - Core object system (everything is an object)
- **command-handler.lisp** - Add new commands here
- **world.lisp** - Build your world here
- **network.lisp** - Client connection handling
- **player.lisp** - Player character system

## 🎯 Next Steps

1. Read `QUICKSTART.md`
2. Follow the quick start above
3. Try the commands in the MUD
4. Read `DEVELOPMENT.md` to add features
5. Build your world!

## 📖 Full Guide

For detailed information, see `00_START_HERE.md` or `INDEX.md`

---

**That's it! You have a working MUD server. Enjoy! 🎮✨**
