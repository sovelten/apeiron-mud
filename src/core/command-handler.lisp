(in-package #:apeiron.core)

(named-readtables:in-readtable pythonic-string-syntax)

(defsection @commands (:title "Commands")
  """The command system turns raw player input into handler calls.
  Every command is registered in *COMMANDS* by DEFINE-COMMAND and
  processed by HANDLE-COMMAND — the full command pipeline, run through
  the world's parser (WORLD-PARSER).  PROCESS-COMMAND is a convenience
  wrapper that routes input through the world's parser.

  While a command runs, the eval helpers ME, HERE and WORLD are bound
  to the current character, room and world, which also makes them
  handy inside the in-game `eval` command."""
  (*commands* variable)
  (define-command macro)
  (handle-command generic-function)
  (split-command function)
  (process-command function)
  (world-parser function)
  (me function)
  (here function)
  (world function)
  (eval-allowed-p function))

(defclass mud-parser ()
  ()
  (:documentation "Base command parser.  A parser runs the full command
pipeline for a line of player input via the HANDLE-COMMAND generic: it
extracts the command name and arguments (resolving them against the
player and world when the parser is context-aware), looks up the
handler, and runs it.  The default method does a plain first-token
split and executes the registered handler.  Subclass MUD-PARSER (or
define your own methods on HANDLE-COMMAND) to build derived parsers —
for example one that understands prepositions and direct/indirect
objects."))

(defgeneric handle-command (parser input player world)
  (:documentation
   "Process INPUT — a raw command line typed by PLAYER in WORLD — into a
command and run it.  This is the full command pipeline: the parser
extracts the command name and arguments (resolving them against PLAYER
and WORLD when it is context-aware), looks up the handler in *COMMANDS*,
and runs it.  Returns whatever the command handler returns (usually
NIL).

PARSER is the parser object doing the work.  The default MUD-PARSER
method does a plain first-token split (see SPLIT-COMMAND) and executes
the registered handler.  Subclass MUD-PARSER (or define your own methods
on HANDLE-COMMAND) to build derived parsers — for example one that
understands prepositions and direct/indirect objects before dispatch."))

;; Command processor
(defvar *commands* (make-hash-table :test #'equal)
  "Hash table of command handlers")

(defmacro define-command (name (world character args) &body body)
  "Define a command handler. WORLD is the mud-world instance,
CHARACTER is the character, ARGS is a raw string that the handler can parse as needed."
  `(setf (gethash ,name *commands*)
         (lambda (,world ,character ,args)
           ,@body)))

;; Built-in commands

(define-command "look" (world character args)
  "Look around the current room to see its description and contents."
  (declare (ignore world args))
  (let ((room (object-location character)))
    (if room
        (character-send-message character (object-long-description room))
        (character-send-message character "You are in a void!"))))

(defun announce-movement (character direction from-room to-room)
  "Announce CHARACTER moving from FROM-ROOM to TO-ROOM in DIRECTION
to the other characters present.

Characters left behind in FROM-ROOM are told \"<name> went <direction>\";
characters already in TO-ROOM are told \"<name> arrives from <direction>\"
(the direction as seen from TO-ROOM, i.e. the exit the mover came through).

If CHARACTER is wearing or holding an item that reacts to movement (see
ON-MOVEMENT), its sound prefixes the announcements: \"You hear a
click-clack sound as ...\".

Returns (values WENT-DIRECTION SOUND): the canonical direction name
(as seen from FROM-ROOM, useful for the mover's own message) and the
sound made by CHARACTER's worn items (so the mover can hear it too)."
  (let* ((conn (connection-find from-room direction))
         (went-direction (if conn
                             (connection-direction-to conn from-room)
                             direction))
         (arrive-direction (if conn
                               (connection-direction-to conn to-room)
                               direction))
         (name (bright-green (object-name character)))
         (sound (character-movement-sound character from-room to-room direction))
         (prefix (if sound
                     (format nil "You hear a ~A sound as " sound)
                     "")))
    ;; Announce departure to the room being left
    (dolist (other (characters-in-room from-room))
      (unless (eq other character)
        (character-send-message
         other
         (format nil "~A~A went ~A" prefix name (yellow went-direction)))))
    ;; Announce arrival to the room being entered
    (dolist (other (characters-in-room to-room))
      (unless (eq other character)
        (character-send-message
         other
         (format nil "~A~A arrives from ~A" prefix name (yellow arrive-direction)))))
    (values went-direction sound)))

(define-command "go" (world character args)
  "Move in a direction, e.g. 'go north', 'go east', 'go south', 'go west'."
  (declare (ignore world))
  (let ((direction args)
        (room (object-location character)))
    (if (zerop (length direction))
        (character-send-message character "Go where? Usage: go <direction>")
        (let ((block-msg (room-exit-blocked-p room character direction)))
          (if block-msg
              (character-send-message character block-msg)
              (let ((target-room (room-exit-target room direction)))
                (if target-room
                    (progn
                      (multiple-value-bind (went-direction sound)
                          (announce-movement character direction room target-room)
                        (object-move character target-room)
                        (character-send-message
                         character
                         (format nil "~A ~A~%"
                                 (if sound
                                     (bright-cyan (format nil "You hear a ~A sound as you went" sound))
                                     (bright-cyan "You went"))
                                 (yellow went-direction)))
                        (character-send-message character (object-long-description target-room))))
                    (character-send-message character "You can't go that way."))))))))

(define-command "n" (world character args)
  "Shorthand for 'go north'."
  (declare (ignore args))
  (process-command world character "go north"))

(define-command "s" (world character args)
  "Shorthand for 'go south'."
  (declare (ignore args))
  (process-command world character "go south"))

(define-command "e" (world character args)
  "Shorthand for 'go east'."
  (declare (ignore args))
  (process-command world character "go east"))

(define-command "w" (world character args)
  "Shorthand for 'go west'."
  (declare (ignore args))
  (process-command world character "go west"))

(define-command "attack" (world character args)
  "Attack a foe in the current room, e.g. 'attack goblin'. Combat is turn-based."
  (let ((room (object-location character)))
    (if (zerop (length args))
        (character-send-message character "Attack whom? Usage: attack <name>")
        (let ((npc (find-npc-in-room room args)))
          (if npc
              (dolist (msg (combat-attack-npc world character npc))
                (character-send-message character msg))
              (character-send-message character "No such foe here."))))))

(define-command "examine" (world character args)
  "Examine an object, NPC, or character in the current room, e.g. 'examine sword'."
  (declare (ignore world))
  (let ((room (object-location character)))
    (if (zerop (length args))
        (character-send-message character "Examine what? Usage: examine <name>")
        (let ((target (first (container-objects-matching room args))))
          (if target
              (character-send-message
               character
               (object-long-description target))
              (character-send-message character "You don't see that here."))))))

(define-command "answer" (world character args)
  "Answer a challenge/riddle in the current room, e.g. 'answer 42'."
  (declare (ignore world))
  (let ((room (object-location character)))
    (if (zerop (length args))
        (character-send-message character "Answer what? Usage: answer <text>")
        (let* ((conn (find-if (lambda (c)
                                (object-get-property c "challenge-answer"))
                              (room-exit-connections room)))
               (expected (and conn (object-get-property conn "challenge-answer")))
               (flag (and conn (object-get-property conn "challenge-flag"))))
          (cond
            ((null expected)
             (character-send-message character "There is no challenge here to answer."))
            ((string= (string-downcase args) (string-downcase expected))
             (object-set-property character flag t)
             (character-send-message character "Correct! The way forward opens."))
            (t
             (character-send-message character "Wrong answer. Try again.")))))))

(define-command "status" (world character args)
  "Show your current status, including hit points (HP)."
  (declare (ignore world args))
  (character-ensure-combat-stats character)
  (let* ((hp (character-hp character))
         (max-hp (character-max-hp character))
         (hp-text (format nil "~D/~D" hp max-hp)))
    (character-send-message character
                         (format nil "HP: ~A"
                                 (if (<= hp (/ max-hp 4))
                                     (bold-red hp-text)
                                     (if (<= hp (/ max-hp 2))
                                         (yellow hp-text)
                                         (bright-green hp-text)))))))

(defvar *eval-character* nil
  "Bound to the current player character during eval command execution.")

(defvar *eval-location* nil
  "Bound to the current character's location during eval command execution.")

(defvar *eval-world* nil
  "Bound to the current world during eval command execution.")

(defun me ()
  "Return the current player character during eval command execution."
  *eval-character*)

(defun here ()
  "Return the current character's location during eval command execution."
  *eval-location*)

(defun world ()
  *eval-world*)

(defun eval-context-package ()
  "Return the eval context package, creating it on first call.
:use's CL and APEIRON.CORE so all core MUD symbols are accessible"
  (or (find-package '#:apeiron.eval)
      (let ((p (make-package '#:apeiron.eval :use nil)))
        (use-package '#:cl p)
        (use-package '#:apeiron.core p)
        p)))

(defun reload-apeiron ()
  "Reload the APEIRON system and re-establish the eval context.
Call this from the MUD via 'eval (reload-apeiron)' after modifying
source files to pick up changes without restarting the server.

ASDF recompiles the files that changed (and everything that depends
on them), so a plain QUICKLOAD is enough for normal git-based
workflows; no forced recompile is needed.

After reloading, re-syncs APEIRON.EVAL with APEIRON.CORE.  If CORE
exported a symbol that a previous /eval form interned in the eval
context (a defvar or defun, say), that local symbol would shadow the
new export.  Uninterning the shadows and re-establishing the :use
makes fresh exports visible without manual intervention."
  (ql:quickload :apeiron)
  ;; Re-sync the eval context package with apeiron.core.  Unintern any
  ;; symbols that shadow newly-exported core symbols (created by earlier
  ;; /eval forms) so the re-established :use sees the fresh exports.
  (let ((p (find-package '#:apeiron.eval)))
    (when p
      (loop for s being the external-symbols of 'apeiron.core
            for existing = (find-symbol (symbol-name s) p)
            do (when (and existing (not (eq existing s)))
                 (unintern existing p)))
      (use-package '#:apeiron.core p)))
  (values))

;; ─── Eval debug helper functions ────────────────────────────────────────────
;; These are available in the eval context (apeiron.eval package) and are
;; designed to help debug/inspect objects from within the game.

(defun d (object)
  "Describe OBJECT, capturing output to a string.
Like CL:DESCRIBE but returns a string instead of printing to *standard-output*.
Example: (d (me))"
  (with-output-to-string (*standard-output*)
    (describe object)))

(defun slots-of (object)
  "Describe all slots of OBJECT, returning a string.
Like CL:DESCRIBE but returns a string instead of printing to *standard-output*.
Example: (slots-of (me))"
  (with-output-to-string (*standard-output*)
    (let ((*print-circle* nil))
      (describe object))))

(defun props (object)
  "Return all properties of OBJECT as a string (from its properties hash-table).
Example: (props (me))"
  (let ((ht (object-properties object)))
    (if (zerop (hash-table-count ht))
        (format nil "No properties on ~A." (object-name object))
        (with-output-to-string (*standard-output*)
          (format t "Properties of ~A:~%" (object-name object))
          (loop for key being the hash-keys of ht
                  using (hash-value val)
                do (format t "  ~S => ~S~%" key val))))))

(defun inv (container)
  "Return the contents of CONTAINER as a string.
Example: (inv (here))"
  (let ((objects (container-all-objects container)))
    (if (null objects)
        (format nil "~A is empty." (object-name container))
        (with-output-to-string (*standard-output*)
          (format t "Contents of ~A:~%" (object-name container))
          (dolist (obj objects)
            (format t "  ~A~%" (object-short-description obj)))))))

(defun loc (object)
  "Return the location chain of OBJECT as a string, from innermost to outermost.
Example: (loc (me)) — shows character -> room -> world containment."
  (with-output-to-string (*standard-output*)
    (loop for obj = object then (object-location obj)
          while obj
          for i from 0
          do (format t "~V@T~A (ID: ~D) [~A]~%"
                     (* i 2)
                     (object-name obj)
                     (object-id obj)
                     (type-of obj)))))

(defun obj-type (object)
  "Return the class/type name of OBJECT as a string.
Useful when ~S printing is too verbose.
Example: (obj-type (me))"
  (format nil "~A" (type-of object)))

(defun obj-find (spec)
  "Find a single object in the current eval world by ID or partial name match.

If SPEC is an integer, looks up the object by world-level ID via WORLD-OBJECT-BY-ID.
If SPEC is a string, returns the first object whose name partially matches
(via WORLD-OBJECTS-MATCHING), or NIL if none match.

Examples:
  (obj-find 42)       ; Find object with world ID 42
  (obj-find \"guard\") ; Find first object matching \"guard\""
  (etypecase spec
    (integer (world-object-by-id *eval-world* spec))
    (string  (first (world-objects-matching *eval-world* spec)))))

(defun eval-allowed-p (character)
  "Return T if CHARACTER may use the in-game `eval` command: either
their owning account is an administrator, or they are wearing an
object with both the \"hat\" and \"wizard\" keywords."
  (or (character-admin-p character)
      (character-wearing-keywords-p character '("hat" "wizard"))))

(define-command "eval" (world character args)
  "Evaluate Lisp code and send output to the character.
Use (me) for the current character, (here) for current room, (world) for the world.
Debug helpers: (d obj), (slots-of obj), (props obj), (inv obj), (loc obj), (obj-type obj), (obj-find name-or-id)
Only administrators (admin accounts) or characters wearing a wizard hat
(an object with both the \"hat\" and \"wizard\" keywords) may use this command."
  (if (not (eval-allowed-p character))
      (character-send-message
       character
       "Only administrators or characters wearing a wizard hat may use eval.")
      (let ((code-str args))
        (if (zerop (length code-str))
            (character-send-message character "Eval what? Usage: eval <code>")
            (let ((*eval-world* world)
                  (*eval-character* character)
                  (*eval-location* (object-location character))
                  (*package* (eval-context-package)))
              (handler-case
                  (let* ((form (read-from-string code-str))
                         (room (object-location character))
                         (result (eval form)))
                    (loop for obj in (container-all-objects room) do
                      (when (and (typep obj 'mud-character)
                                 (not (eq obj character)))
                        (character-send-message obj
                                             (format nil "~A casts the spell: ~A"
                                                     (object-name character) form))))
                    (character-send-message character (format nil "~A" result)))
                (error (e)
                  (character-send-message character (format nil "Error: ~A" e)))))))))

(define-command "exits" (world character args)
  "List the visible exits from the current room."
  (declare (ignore world args))
  (let ((room (object-location character)))
    (let ((exits (mapcar #'first (room-exit-list room))))
      (if exits
          (character-send-message character (format nil "~A~{~A~^, ~}"
                                              (bold-white "Exits: ")
                                              (mapcar #'yellow exits)))
          (character-send-message character "There are no exits here.")))))

(define-command "inventory" (world character args)
  "Show what you are carrying in your inventory."
  (declare (ignore world args))
  (let ((inv (container-all-objects character)))
    (if (null inv)
        (character-send-message character "You are not carrying anything.")
        (character-send-message character
                             (format nil "~A~%~{~A~%~}"
                                     (bold-white "You are carrying:")
                                     (mapcar (lambda (obj)
                                               (format nil "  - ~A" (object-short-description obj)))
                                             inv))))))

(defun wear-result-message (item limb reason &optional requested-limb)
  "Build the player-facing message for a WEAR result.
ITEM is the item attempted, LIMB the limb equipped (or NIL on failure),
REASON one of the WEAR result keywords, REQUESTED-LIMB the limb name the
player asked for (for :no-such-limb)."
  (ecase reason
    (:ok
     (let ((verb (if (hand-limb-p limb) "hold" "wear"))
           (prep (if (hand-limb-p limb) "in" "on")))
       (format nil "You ~A ~A ~A your ~A."
               verb (object-name item) prep (object-name limb))))
    (:no-such-limb
     (format nil "You don't have a ~A to wear that on." requested-limb))
    (:no-fitting-limb
     (format nil "You can't wear ~A — nothing fits it." (object-name item)))
    (:keywords-dont-match
     (format nil "~A doesn't belong on your ~A."
             (object-name item) (object-name limb)))
    (:occupied
     (format nil "Your ~A already holds ~A."
             (object-name limb) (object-name (limb-item limb))))
    (:not-in-inventory
     (format nil "You aren't carrying ~A." (object-name item)))))

(define-command "wear" (world character args)
  "Wear or hold an item you are carrying, e.g. 'wear wizard hat', 'wear sword on left hand'."
  (declare (ignore world))
  (if (zerop (length args))
      (character-send-message character "Wear what? Usage: wear <item> [on <limb>]")
      (let* ((on-pos (search " on " args))
             (item-name (if on-pos
                            (string-trim '(#\Space #\Tab) (subseq args 0 on-pos))
                            args))
             (limb-name (and on-pos
                             (string-trim '(#\Space #\Tab) (subseq args (+ on-pos 4)))))
             (item (first (container-objects-matching character item-name))))
        (if (null item)
            (character-send-message
             character
             (format nil "You aren't carrying ~A." item-name))
            (multiple-value-bind (limb reason) (wear character item limb-name)
              (character-send-message
               character
               (wear-result-message item limb reason limb-name))
              (when (eq reason :ok)
                ;; Give the item a chance to react to being worn/held.
                (funcall (if (hand-limb-p limb) #'handle-hold #'handle-wear)
                         item character)))))))


(define-command "remove" (world character args)
  "Remove an equipped item and put it in your inventory, e.g. 'remove hat'."
  (declare (ignore world))
  (if (zerop (length args))
      (character-send-message character "Remove what? Usage: remove <item>")
      (let ((pair (find-if (lambda (pair) (object-name-matches (cdr pair) args))
                           (character-worn-items character))))
        (if (null pair)
            (character-send-message
             character
             (format nil "You aren't wearing or holding ~A." args))
            (progn
              (unequip character (cdr pair))
              (character-send-message
               character
               (format nil "You remove ~A from your ~A."
                       (object-name (cdr pair))
                       (object-name (car pair)))))))))


(define-command "get" (world character args)
  "Pick up an object from the room, e.g. 'get hat'.  'take' is an alias."
  (declare (ignore world))
  (if (zerop (length args))
      (character-send-message character "Get what? Usage: get <item>")
      (let* ((room (object-location character))
             (target (first (container-objects-matching room args))))
        (cond
          ((null target)
           (character-send-message character (format nil "You don't see ~A here." args)))
          ((typep target 'mud-character)
           (character-send-message character "You can't pick that up."))
          (t
           (container-remove-object room target)
           (container-add-object character target)
           (character-send-message
            character
            (format nil "You pick up ~A." (object-name target))))))))


(define-command "drop" (world character args)
  "Put down an object from your inventory into the room, e.g. 'drop hat'."
  (declare (ignore world))
  (if (zerop (length args))
      (character-send-message character "Drop what? Usage: drop <item>")
      (let* ((room (object-location character))
             (target (first (container-objects-matching character args))))
        (if (null target)
            (character-send-message character (format nil "You aren't carrying ~A." args))
            (progn
              (container-remove-object character target)
              (container-add-object room target)
              (character-send-message
               character
               (format nil "You drop ~A." (object-name target))))))))

;; 'take' is an alias for 'get'
(setf (gethash "take" *commands*) (gethash "get" *commands*))

(define-command "say" (world character args)
  "Say something aloud to everyone in the current room, e.g. 'say Hello!'."
  (declare (ignore world))
  (let ((message args))
    (if (zerop (length message))
        (character-send-message character "Say what?")
        (let ((room (object-location character)))
          (character-send-message character (format nil "~A: ~A" (bold-white "You say") message))
          (loop for obj in (container-all-objects room) do
            (when (and (typep obj 'mud-character)
                       (not (eq obj character)))
              (character-send-message obj
                                  (format nil "~A: ~A" 
                                          (bright-green (format nil "~A says" (object-name character))) message))))))))

(define-command "shout" (world character args)
  "Shout a message that is heard by all characters in all rooms, e.g. 'shout Help!'."
  (let ((message args))
    (if (zerop (length message))
        (character-send-message character "Shout what? Usage: shout <message>")
        (progn
          (world-broadcast world
                           (format nil "~A: ~A" 
                                   (bold-red (format nil "~A shouts" (object-name character)))
                                   message)
                           character)
          (character-send-message character (format nil "~A: ~A" (bold-red "You shout") message))))))

(define-command "read" (world character args)
  "Read a readable object in the room or your inventory, e.g. 'read guestbook'."
  (declare (ignore world))
  (if (zerop (length args))
      (character-send-message character "Read what? Usage: read <name>")
      (let* ((room (object-location character))
             (target (or (first (container-objects-matching room args))
                         (first (container-objects-matching character args)))))
        (cond
          ((null target)
           (character-send-message character "You don't see that here."))
          ((handle-read target character))
          (t
           (character-send-message character (format nil "There's nothing to read on the ~A." (object-name target))))))))

(define-command "write" (world character args)
  "Write a message on a writable object in the room, e.g. 'write guestbook'."
  (declare (ignore world))
  (if (zerop (length args))
      (character-send-message character "Write on what? Usage: write <name>")
      (let* ((room (object-location character))
             (target (or (first (container-objects-matching room args))
                         (first (container-objects-matching character args)))))
        (cond
          ((null target)
           (character-send-message character "You don't see that here."))
          (t
           (let* ((session (character-session character))
                  (message (ask-input session "What do you want to write?")))
             (if (zerop (length message))
                 (character-send-message character "Write what? Please try again.")
                 (unless (handle-write target character message)
                   (character-send-message character (format nil "There's nothing to write on the ~A." (object-name target)))))))))))

(define-command "help" (world character args)
  "Show a list of commands, or show help for a specific command with 'help <command>'."
  (declare (ignore world))
  (if (plusp (length args))
      ;; Specific command help
      (let* ((cmd-name (string-downcase (string-trim '(#\Space #\Tab) args)))
             (handler (gethash cmd-name *commands*)))
        (if handler
            (let ((doc (documentation handler 'function)))
              (if doc
                  (character-send-message character
                                       (format nil "~A~%~A"
                                               (bold-white (format nil "Help for '~A':" cmd-name))
                                               doc))
                  (character-send-message character
                                       (format nil "No help available for '~A'." cmd-name))))
            (character-send-message character
                                 (format nil "Unknown command '~A'. Type 'help' for available commands."
                                         cmd-name))))
      ;; List all commands
      (let ((cmd-list (sort (loop for key being the hash-keys of *commands*
                                  collect (cyan key))
                            #'string< :key #'string)))
        (character-send-message character
                             (format nil "~A~%~{~A~%~}~%Type 'help <command>' for more info."
                                     (bold-white "Available commands:")
                                     cmd-list)))))

(define-command "toggle-colors" (world character args)
  "Toggle ANSI color output on/off for your session."
  (declare (ignore world args))
  (let* ((session (character-session character))
         (new-value (not (session-use-colors session))))
    (setf (session-use-colors session) new-value)
    ;; Rebinds *COLORIZE* to the new value so the response message
    ;; respects the toggle (process-command already bound it to the old value)
    (let ((*colorize* new-value))
      (character-send-message character
                           (format nil "Colors ~A."
                                   (if new-value
                                       (bright-green "enabled")
                                       (red "disabled")))))))

(define-command "quit" (world character args)
  "Disconnect from the game."
  (declare (ignore args))
  (character-send-message character "Goodbye!")
  (let ((session (character-session character)))
    ;; Clear session-character FIRST — world-remove-character! may
    ;; destroy the BKNR object (for guest characters), so prevent
    ;; handle-client cleanup from double-processing it.
    (setf (session-character session) nil)
    (world-remove-character! world character)
    (session-disconnect session)))

(define-command "tell" (world character args)
  "Send a private message to a character or speak to an object in the room, e.g. 'tell bob hello'."
  (declare (ignore world))
  (if (zerop (length args))
      (character-send-message character "Tell who what? Usage: tell <name> <message>")
      (let* ((space-pos (position #\Space args))
             (target-name (if space-pos
                              (string-downcase (subseq args 0 space-pos))
                              (string-downcase args)))
             (message (if space-pos
                          (string-trim '(#\Space #\Tab) (subseq args (1+ space-pos)))
                          "")))
        (if (zerop (length message))
            (character-send-message character "Tell who what? Usage: tell <name> <message>")
            (let* ((room (object-location character))
                   (target (first (container-objects-matching room target-name))))
              (cond
                ((null target)
                 (character-send-message character (format nil "There's no ~A here to tell that to." args)))
                ((typep target 'mud-character)
                 ;; Send private message to another character
                 (character-send-message character (format nil "~A ~A ~A" (bold-white "You tell") (bright-green (format nil "~A:" (object-name target))) message))
                 (character-send-message target (format nil "~A ~A ~A" (bright-green (format nil "~A tells you" (object-name character))) (bold-white "privately:") message)))
                (t
                 ;; Tell an object — give it a chance to handle the speech
                 (character-send-message character (format nil "~A ~A ~A" (bold-white "You tell") (cyan (format nil "~A:" (object-name target))) message))
                 (unless (handle-tell target character message)
                   ;; Object didn't respond
                   (character-send-message character (format nil "~A doesn't seem to understand." (object-name target)))))))))))

(defun split-command (input)
  "Split INPUT into a command name and raw args string.
Returns (values COMMAND-NAME RAW-ARGS-STRING).  This is the raw
building block the default parser uses; derived parsers can call it
directly to reuse the plain first-token split."
  (let ((trimmed (string-trim '(#\Space #\Tab) input)))
    (if (zerop (length trimmed))
        (values nil "")
        (let ((space-pos (position #\Space trimmed)))
          (if space-pos
              (values (string-downcase (subseq trimmed 0 space-pos))
                      (string-trim '(#\Space #\Tab) (subseq trimmed (1+ space-pos))))
              (values (string-downcase trimmed) ""))))))

(defmethod handle-command ((parser mud-parser) input player world)
  "Default command processing: split INPUT into a command name and raw
args, look up the handler in *COMMANDS*, and run it.  Honors the
character's session color preference by binding *COLORIZE*.

Returns whatever the command handler returns (usually NIL)."
  (declare (ignore parser))
  ;; Issue an event for every line of character input (for debugging/logging).
  (let ((session (character-session player)))
    (issue-character-input-event (session-id session)
                                 (object-name player)
                                 input))

  (when (> (length input) +max-command-length+)
    (character-send-message player "Command too long.")
    (return-from handle-command nil))

  (multiple-value-bind (command args) (split-command input)
    (if (not command)
        (return-from handle-command nil))

    (let ((handler (gethash command *commands*)))
      (if handler
          (let ((*colorize* (session-use-colors (character-session player))))
            (handler-case
                (funcall handler world player args)
              (error (e)
                (log-error "Command error for ~A: ~A" (object-name player) e)
                (character-send-message player "Error executing command."))))
          (character-send-message player "Unknown command. Type 'help' for available commands.")))))

(defun process-command (world character command-string)
  "Process a command from a character.
Convenience wrapper around HANDLE-COMMAND using the world's parser."
  (handle-command (world-parser world) command-string character world))
