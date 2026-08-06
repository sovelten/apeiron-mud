# World-Building Tutorial: Create a Secret Room

This tutorial walks you through creating a **password-protected secret room** containing a **secret diary** (guestbook).  
We'll use the in-game `eval` command, which runs Lisp code inside the live server — no restart required.

## The Plan

1. Create a hidden room: *The Ancient Library*
2. Create a secret diary (guestbook) and place it in the library
3. Connect the library to **the room you are standing in** through a *crack in the wall*
4. Lock the passage with a password challenge — characters must `answer` correctly to enter

## Step-by-Step

### 1. Connect to the server

```bash
telnet localhost 8888
```

Log in with any name. You'll start in the hub room, your current location.

### 2. Create the secret room

Use `eval` to create a new room:

```
> eval (world-add-object! (world) (new-room :name "The Ancient Library" :description "A dusty hidden library lit by a single flickering candle. Shelves of crumbling books line the walls."))

#<MUD-ROOM The Ancient Library (ID: 12)>
```

The return value shows the new room and its world-level ID (yours will differ — note it for later).

### 3. Create a secret diary (guestbook)

```
> eval (world-add-object! (world) (new-guestbook :name "a worn leather diary" :aliases '("diary")))

#<MUD-GUESTBOOK a worn leather diary (ID: 13)>
```

### 4. Place the diary in the secret room

```
> eval (container-add-object (world-object-by-id (world) 12) (world-object-by-id (world) 13))

#<MUD-GUESTBOOK a worn leather diary (ID: 13)>
```

Replace `12` and `13` with the IDs you got in steps 2 and 3.

### 5. Connect the library to your current room

```
> eval (connect-rooms! (world) (here) "north" (world-object-by-id (world) 12) "south" :name "a crack in the wall")

#<MUD-CONNECTION a crack in the wall (ID: 14)>
```

A character in the hub room can now `go north` and find the crack, and a character in the library can `go south` back.

### 6. Add the password challenge

Lock the connection with a password. Characters must type `answer <password>` to pass:

```
> eval (connection-set-challenge (connection-find (here) "north") "The wall whispers: 'Speak the password.'" "open-sesame" "has-heard-secret")

NIL
```

This sets up three things on the *crack in the wall* connection:

| Property | Your value | Purpose |
|---|---|---|
| `challenge-question` | `"The wall whispers: 'Speak the password.'"` | Shown to characters who try to pass without answering |
| `challenge-answer` | `"open-sesame"` | The correct answer (case-insensitive) |
| `challenge-flag` | `"has-heard-secret"` | A flag set on the character after a correct answer; once set, the character can pass freely |

### 7. Test it

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

### 8. Read and write in the secret diary

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

## Summary of Functions Used

| Function | Purpose |
|---|---|
| `new-room` | Create a new room |
| `new-guestbook` | Create a new guestbook (entries are persisted as CSV) |
| `world-add-object!` | Register an object/room in the world |
| `world-object-by-id` | Look up an object by its world-level ID |
| `container-add-object` | Place an object inside a container (room, character, etc.) |
| `connect-rooms!` | Create a bidirectional connection between two rooms |
| `connection-find` | Find the connection leaving a room in a given direction |
| `connection-set-challenge` | Lock a connection with a question/answer/flag challenge |
| `here` | Returns the current character's room (handy in `eval`) |
| `world` | Returns the current world (handy in `eval`) |

## Tips

- **Use `here` instead of IDs**: `(here)` returns the room you're standing in, so `(connect-rooms! (world) (here) "north" ...)` saves you from looking up IDs.
- **Check your work**: `(room-exit-list (here))` lists all exits from the current room.
- **All eval is persistent**: Every room, guestbook, and connection created this way is automatically saved to the BKNR datastore and survives server restarts.
- **Guestbook CSV persistence**: Guestbook entries are written to a CSV file in the `data/` directory and reloaded on server restart.
