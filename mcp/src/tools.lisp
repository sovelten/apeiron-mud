;;;; mcp/src/tools.lisp — MCP tool definitions
;;;;
;;;; Defines the tools exposed by the apeiron-mcp server.  Each tool
;;;; has a descriptor (name, description, input schema) and a handler
;;;; function that implements the tool's behavior.
;;;;
;;;; Tools:
;;;;   mud-connect    — Connect to the MUD server
;;;;   mud-send       — Send any command to the MUD
;;;;   mud-eval       — Execute arbitrary Lisp code in the MUD world
;;;;   mud-disconnect — Disconnect from the MUD
;;;;   mud-status     — Check connection status
;;;;
;;;; The tool registry is a simple hash-table mapping tool names to
;;;; (descriptor . handler) pairs.  This is intentionally kept simple
;;;; — no macros, no code generation — so the server remains focused
;;;; and easy to audit.

(in-package #:apeiron-mcp/src/package)

;; ─── Helpers ────────────────────────────────────────────────────

(defun %make-ht (&rest kvs)
  "Create a hash-table with string keys from alternating keyword-value pairs.
Example: (%make-ht \"name\" \"look\" \"type\" \"string\")"
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on kvs by #'cddr
          do (setf (gethash k ht) v))
    ht))

(defun %tool-schema (name description &rest prop-specs)
  "Build a complete MCP tool descriptor hash-table.

NAME and DESCRIPTION are strings.
PROP-SPECS is a list of property definitions, each of the form:
  (prop-name type description &key required-p default)

Returns a hash-table suitable for inclusion in tools/list response."
  (let ((properties (make-hash-table :test 'equal))
        (required '()))
    (dolist (spec prop-specs)
      (destructuring-bind (prop-name type desc &key required-p default) spec
        (let ((prop (make-hash-table :test 'equal)))
          (setf (gethash "type" prop) (string-downcase (string type)))
          (when desc
            (setf (gethash "description" prop) desc))
          (when default
            (setf (gethash "default" prop) default))
          (setf (gethash prop-name properties) prop)
          (when required-p
            (push prop-name required)))))
    (%make-ht
     "name" name
     "description" description
     "inputSchema" (%make-ht
                    "type" "object"
                    "properties" properties
                    "required" (coerce (nreverse required) 'vector)))))

(defun %arg (args name &key default)
  "Extract a named argument from the ARGS hash-table.
Returns DEFAULT if the key is missing or if ARGS is NIL.
String values are coerced to simple-strings."
  (if (and args (hash-table-p args))
      (let ((val (multiple-value-bind (v present) (gethash name args)
                   (if present v default))))
        (if (stringp val)
            (coerce val 'simple-string)
            val))
      default))

(defun %require-arg (args name description)
  "Extract a required argument, signaling an error if missing.
String values are coerced to simple-strings because YASON may produce
adjustable strings that usocket and telnet reject."
  (let ((val (%arg args name)))
    (when (or (null val) (and (stringp val) (string= val "")))
      (error "Missing required argument: ~A (~A)" name description))
    (if (stringp val)
        (coerce val 'simple-string)
        val)))

;; ─── Tool registry ──────────────────────────────────────────────

(defvar *tool-registry* (make-hash-table :test 'equal)
  "Hash-table mapping tool name string → (descriptor-ht . handler-fn).")

(defun %register-tool (name descriptor handler)
  "Register a tool with the given NAME, DESCRIPTOR hash-table, and HANDLER function."
  (setf (gethash name *tool-registry*) (cons descriptor handler)))

(defun %get-tool-descriptors ()
  "Return a vector of all tool descriptor hash-tables."
  (let ((descriptors '()))
    (maphash (lambda (k v)
               (declare (ignore k))
               (push (car v) descriptors))
             *tool-registry*)
    (coerce (nreverse descriptors) 'vector)))

(defun %get-tool-handler (name)
  "Return the handler function for the tool named NAME, or NIL."
  (let ((entry (gethash name *tool-registry*)))
    (when entry
      (cdr entry))))

;; ─── Response builders ──────────────────────────────────────────

(defun %result (id payload)
  "Build a JSON-RPC 2.0 success response hash-table."
  (%make-ht "jsonrpc" "2.0" "id" id "result" payload))

(defun %error (id code message)
  "Build a JSON-RPC 2.0 error response hash-table."
  (%make-ht "jsonrpc" "2.0" "id" id
            "error" (%make-ht "code" code "message" message)))

(defun %text-content (text)
  "Build an MCP content vector containing a single text block."
  (vector (%make-ht "type" "text" "text" text)))

;; ─── Tool: mud-connect ──────────────────────────────────────────

(%register-tool
 "mud-connect"
 (%tool-schema
  "mud-connect"
  "Connect to the Apeiron MUD server as a player character.

After connecting, you can use mud-send to issue any MUD command
(look, go, examine, attack, say, shout, inventory, help, etc.)
and mud-eval to run arbitrary Common Lisp code in the game world.

The MUD supports 15 commands: look, go <direction>, exits, examine <name>,
attack <name>, status, answer <text>, say <message>, shout <message>,
read, write, inventory, help, toggle-colors, quit, and
eval <lisp-code> (which runs in the game's Lisp environment with
me (your character), here (current room), and world bound)."
  '("host" :string "MUD server hostname (e.g. \"localhost\")"
    :required-p t)
  '("port" :integer "MUD server port" :default 8888)
  '("name" :string "Player character name" :required-p t))

 (lambda (id args)
   (handler-case
       (let* ((host (%require-arg args "host" "MUD server hostname"))
              (port (or (%arg args "port") 8888))
              (name (%require-arg args "name" "Player character name")))
         (multiple-value-bind (welcome err status)
             (connect-to-mud host port name)
           (if (eq status :ok)
               (%result id (%make-ht "content" (%text-content welcome)
                                     "isError" nil))
               (%result id (%make-ht "content" (%text-content err)
                                     "isError" t)))))
     (error (e)
       (%error id -32000 (format nil "mud-connect failed: ~A" e))))))

;; ─── Tool: mud-send ─────────────────────────────────────────────

(%register-tool
 "mud-send"
 (%tool-schema
  "mud-send"
  "Send a command to the Apeiron MUD server and return the response.

Available commands:
  look           — Describe current room (name, description, contents, exits)
  go <dir>       — Move in a direction (north, south, east, west, or custom)
  exits          — List available exits
  examine <name> — Examine an NPC or object in the room
  attack <name>  — Attack an NPC in the room
  status         — Show your HP (color-coded)
  answer <text>  — Answer a challenge/riddle blocking an exit
  say <message>  — Speak to other players in the same room
  shout <msg>    — Broadcast to all players in the world
  read           — Read the guestbook in the room or inventory
  write          — Write an entry in the guestbook (interactive)
  inventory      — List items carried
  help           — List all commands
  toggle-colors  — Enable/disable ANSI colors
  quit           — Disconnect (prefer mud-disconnect instead)

The response is the server output with ANSI color codes stripped."
  '("command" :string "The MUD command to execute" :required-p t))

 (lambda (id args)
   (handler-case
       (let ((command (%require-arg args "command" "MUD command")))
         (multiple-value-bind (response err)
             (send-command command)
           (if err
               (%result id (%make-ht "content" (%text-content
                                                (format nil "Error: ~A~%~@[Response: ~A~]"
                                                        err response))
                                     "isError" t))
               (%result id (%make-ht "content" (%text-content (or response "(no output)"))
                                     "isError" nil)))))
     (error (e)
       (%error id -32000 (format nil "mud-send failed: ~A" e))))))

;; ─── Tool: mud-eval ─────────────────────────────────────────────

(%register-tool
 "mud-eval"
 (%tool-schema
  "mud-eval"
  "Execute arbitrary Common Lisp code in the Apeiron MUD game world.

The code runs in the APEIRON.EVAL package with these functions available:
  (me)    — Returns your mud-character object
  (here)  — Returns the mud-room you are currently in
  (world) — Returns the mud-world instance

Accessors you can use:
  (object-name obj)     — Get the name of any object
  (object-location obj) — Get the location of an object (room)
  (object-id obj)       — Get the unique ID of an object
  (room-exits room)     — Get list of exit directions from a room
  (contents obj)        — Get list of objects contained in a room/character

This is the most powerful tool available. You can:
  - Inspect objects: (describe (me)), (object-name (here))
  - List all players: (alexandria:hash-table-values (players (world)))
  - Teleport: (setf (object-location (me)) some-room)
  - Check stats: (character-hp (me))

Be careful: code runs with full access to the running game world.
Use this to explore, build, and manipulate the world dynamically."
  '("code" :string "Common Lisp expression to evaluate in the game world"
    :required-p t))

 (lambda (id args)
   (handler-case
       (let ((code (%require-arg args "code" "Lisp code to evaluate")))
         (multiple-value-bind (response err)
             (send-eval code)
           (if err
               (%result id (%make-ht "content" (%text-content
                                                (format nil "Error: ~A~%~@[Response: ~A~]"
                                                        err response))
                                     "isError" t))
               (%result id (%make-ht "content" (%text-content (or response "(no output)"))
                                     "isError" nil)))))
     (error (e)
       (%error id -32000 (format nil "mud-eval failed: ~A" e))))))

;; ─── Tool: mud-disconnect ───────────────────────────────────────

(%register-tool
 "mud-disconnect"
 (%tool-schema
  "mud-disconnect"
  "Disconnect from the Apeiron MUD server gracefully.
Sends the 'quit' command and closes the telnet connection.")

 (lambda (id args)
   (declare (ignore args))
   (handler-case
       (multiple-value-bind (msg err)
           (disconnect-from-mud)
         (if err
             (%result id (%make-ht "content" (%text-content err) "isError" t))
             (%result id (%make-ht "content" (%text-content msg) "isError" nil))))
     (error (e)
       (%error id -32000 (format nil "mud-disconnect failed: ~A" e))))))

;; ─── Tool: mud-status ───────────────────────────────────────────

(%register-tool
 "mud-status"
 (%tool-schema
  "mud-status"
  "Check the current connection status to the Apeiron MUD server.
Returns whether you are connected and basic connection info.
Use this to verify your connection before sending commands.")

 (lambda (id args)
   (declare (ignore args))
   (let ((status (connection-status)))
     (%result id (%make-ht "content" (%text-content status) "isError" nil)))))

;; ─── Tool: mud-listen ───────────────────────────────────────────

(%register-tool
 "mud-listen"
 (%tool-schema
  "mud-listen"
  "Wait for activity from the MUD server without sending a command.

Blocks until something happens in the game (another player speaks,
enters the room, attacks, etc.) or the timeout expires.  This enables
the LLM to wait for and react to in-game events rather than polling.

When something happens, returns the MUD output (with ANSI codes stripped).
When the timeout expires with no activity, returns a timeout message.
Use the 'timeout' parameter (default 60 seconds) to control how long
to wait.  Set timeout to a lower value (e.g. 10) to poll briefly."
  '("timeout" :number "Seconds to wait (default 60)"
    :default 60))

 (lambda (id args)
   (handler-case
       (let ((timeout (or (%arg args "timeout") 60)))
         (multiple-value-bind (text err status)
             (listen-for-activity :timeout timeout :idle-timeout 1.0)
           (cond
             ((eq status :timeout)
              (%result id (%make-ht "content" (%text-content "No activity (timeout).")
                                    "isError" nil)))
             ((eq status :error)
              (%result id (%make-ht "content" (%text-content (or err text "Error"))
                                    "isError" t)))
             (t
              (%result id (%make-ht "content" (%text-content (or text "(no output)"))
                                    "isError" nil))))))
     (error (e)
       (%error id -32000 (format nil "mud-listen failed: ~A" e))))))
