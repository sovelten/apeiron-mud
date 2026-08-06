# Wordle Puzzle Game

A Wordle-like puzzle game you can drop into any room. Each puzzle has a secret 5-letter word, and characters guess it by telling the puzzle their guesses. Each character's progress is tracked independently, so everyone can play simultaneously.

## Create a Wordle Puzzle

Use `eval` to create a puzzle and place it in your current room:

```
> eval (let ((p (new-wordle-puzzle)))
         (container-add-object (here) p)
         (create-object! (world) p))

#<MUD-WORDLE-PUZZLE a Wordle puzzle board (ID: 25)>
```

The puzzle uses today's **daily word** — determined by the current date, so all
characters see the same word each day and it changes daily.  Each puzzle
instance picks its own random **seed**, so two puzzles created on the same day
will have *different* daily words — great for multiple boards in different
rooms.

| Parameter | Default | Description |
|---|---|---|
| `:name` | `"a Wordle puzzle board"` | Display name of the puzzle |
| `:description` | *(default description)* | What characters see when examining or viewing the board |
| `:target-word` | today's daily word | The 5-letter word to guess (omit for date-based daily word) |
| `:max-guesses` | `6` | How many guesses characters get |
| `:word-list` | `*wordle-default-words*` | A vector of valid 5-letter words to pick from |
| `:seed` | random | Per-instance seed for daily word selection; pass the same seed to get reproducible daily words |

**Portuguese (pt-BR) puzzles** — use the built-in Portuguese word list:

```
> eval (let ((p (new-wordle-puzzle
                :word-list *wordle-pt-br-words*)))
         (container-add-object (here) p)
         (create-object! (world) p))
```

Portuguese words include accented characters (á, â, ã, ç, é, ê, í, ó, ô, õ, ú).
Players can type plain ASCII letters and the puzzle matches them
accent-insensitively - e.g. guessing `macas` matches target `maçãs`.

**Reproducible puzzles** — pass the same `:seed` to create multiple instances
that share the same daily word rotation:

```
> eval (new-wordle-puzzle :seed 42 :name "Daily Challenge")
```

## Play the Game

Interact with the puzzle using the `tell` command (whisper privately to it — other characters won't see your guesses):

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

When someone solves or fails the puzzle, other characters in the room are notified:
```
Alice solved the Wordle puzzle!
```

## Advanced: Custom Puzzle

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
| `:description` | *(default description)* | What characters see when examining or viewing the board |
| `:target-word` | today's daily word | The 5-letter word to guess (omit for date-based daily word) |
| `:max-guesses` | `6` | How many guesses characters get |
| `:word-list` | `*wordle-default-words*` | A vector of valid 5-letter words to pick from; see `*wordle-pt-br-words*` for Portuguese |
| `:seed` | random | Per-instance seed for daily word selection |

## Reset a Puzzle

Reset all character progress (keeping the same word) or set a new word:

```
> eval (wordle-reset (world-object-with-name (world) "Riddle Sphinx"))

T

> eval (wordle-reset (world-object-with-name (world) "Riddle Sphinx") :new-word "magic")

T
```

## Admin: Place in a Specific Room

Find a room by name and place the puzzle there:

```
> eval (let ((p (new-wordle-puzzle :target-word "world"))
             (room (world-object-with-name (world) "The Gathering")))
         (container-add-object room p)
         (create-object! (world) p))

#<MUD-WORDLE-PUZZLE a Wordle puzzle board (ID: 27)>
```

## Persistence

Wordle puzzles are fully persistent. The word list and max guesses are saved to the BKNR datastore. Per-character guess state and the daily word are ephemeral (the puzzle recalculates its daily word on server restart). If you want a permanent fixed word, pass `:target-word` explicitly when creating the puzzle. To add a puzzle to the default world permanently, include it in the world builder function in `src/worlds/world-areas.lisp`.
