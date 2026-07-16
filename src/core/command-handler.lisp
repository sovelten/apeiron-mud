(in-package #:apeiron.core)

;; Command processor
(defvar *commands* (make-hash-table :test #'equal)
  "Hash table of command handlers")

(defmacro define-command (name (world player args) &body body)
  "Define a command handler. WORLD is the mud-world instance,
PLAYER is the character, ARGS is a raw string that the handler can parse as needed."
  `(setf (gethash ,name *commands*)
         (lambda (,world ,player ,args)
           ,@body)))

;; Built-in commands

(define-command "look" (world player args)
  (declare (ignore world args))
  (let ((room (object-location player)))
    (if room
        (player-send-message player (object-describe room))
        (player-send-message player "You are in a void!"))))

(define-command "go" (world player args)
  (declare (ignore world))
  (let ((direction args)
        (room (object-location player)))
    (if (zerop (length direction))
        (player-send-message player "Go where? Usage: go <direction>")
        (let ((block-msg (room-exit-blocked-p room player direction)))
          (if block-msg
              (player-send-message player block-msg)
              (let ((target-room (room-exit-target room direction)))
                (if target-room
                    (progn
                      (object-move player target-room)
                      (player-send-message player (format nil "~A ~A~%" (bright-cyan "You go") (yellow direction)))
                      (player-send-message player (object-describe target-room)))
                    (player-send-message player "You can't go that way."))))))))

(define-command "n" (world player args)
  (declare (ignore args))
  (process-command world player "go north"))

(define-command "s" (world player args)
  (declare (ignore args))
  (process-command world player "go south"))

(define-command "e" (world player args)
  (declare (ignore args))
  (process-command world player "go east"))

(define-command "w" (world player args)
  (declare (ignore args))
  (process-command world player "go west"))

(define-command "attack" (world player args)
  (let ((room (object-location player)))
    (if (zerop (length args))
        (player-send-message player "Attack whom? Usage: attack <name>")
        (let ((npc (find-npc-in-room room args)))
          (if npc
              (dolist (msg (combat-attack-npc world player npc))
                (player-send-message player msg))
              (player-send-message player "No such foe here."))))))

(define-command "examine" (world player args)
  (declare (ignore world))
  (let* ((room (object-location player))
         (target-name (string-downcase args)))
    (if (zerop (length args))
        (player-send-message player "Examine what? Usage: examine <name>")
        (let ((target
               (or (find-npc-in-room room args)
                   (find-if (lambda (obj)
                              (and (not (eq obj player))
                                   (or (search target-name (string-downcase (object-name obj)))
                                       (some (lambda (alias)
                                               (string-equal target-name alias))
                                             (object-aliases obj)))))
                            (container-all-objects room)))))
          (if target
              (player-send-message
               player
               (object-describe target))
              (player-send-message player "You don't see that here."))))))

(define-command "answer" (world player args)
  (declare (ignore world))
  (let ((room (object-location player)))
    (if (zerop (length args))
        (player-send-message player "Answer what? Usage: answer <text>")
        (let* ((conn (find-if (lambda (c)
                                (object-get-property c "challenge-answer"))
                              (room-connections room)))
               (expected (and conn (object-get-property conn "challenge-answer")))
               (flag (and conn (object-get-property conn "challenge-flag"))))
          (cond
            ((null expected)
             (player-send-message player "There is no challenge here to answer."))
            ((string= (string-downcase args) (string-downcase expected))
             (object-set-property player flag t)
             (player-send-message player "Correct! The way forward opens."))
            (t
             (player-send-message player "Wrong answer. Try again.")))))))

(define-command "status" (world player args)
  (declare (ignore world args))
  (player-ensure-combat-stats player)
  (let* ((hp (player-hp player))
         (max-hp (player-max-hp player))
         (hp-text (format nil "~D/~D" hp max-hp)))
    (player-send-message player
                         (format nil "HP: ~A"
                                 (if (<= hp (/ max-hp 4))
                                     (bold-red hp-text)
                                     (if (<= hp (/ max-hp 2))
                                         (yellow hp-text)
                                         (bright-green hp-text)))))))

(defvar *eval-player* nil
  "Bound to the current player character during eval command execution.")

(defvar *eval-location* nil
  "Bound to the current player's location during eval command execution.")

(defvar *eval-world* nil
  "Bound to the current world during eval command execution.")

(defun me ()
  "Return the current player character during eval command execution."
  *eval-player*)

(defun here ()
  "Return the current player's location during eval command execution."
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

(define-command "eval" (world player args)
  (declare (ignore world))
  (let ((code-str args))
    (if (zerop (length code-str))
        (player-send-message player "Eval what? Usage: eval <code>")
        (let ((*eval-world* world)
              (*eval-player* player)
              (*eval-location* (object-location player))
              (*package* (eval-context-package)))
          (handler-case
              (let* ((form (read-from-string code-str))
                     (room (object-location player))
                     (result (eval form)))
                (loop for obj in (container-all-objects room) do
                  (when (and (typep obj 'mud-character)
                             (not (eq obj player)))
                    (player-send-message obj (format nil "~A casts the spell: ~A" (object-name player) form))
                    (player-send-message obj (format nil "~A" result))))
                (player-send-message player (format nil "~A" result)))
            (error (e)
              (player-send-message player (format nil "Error: ~A" e))))))))

(define-command "exits" (world player args)
  (declare (ignore world args))
  (let ((room (object-location player)))
    (let ((exits (mapcar #'first (room-exit-list room))))
      (if exits
          (player-send-message player (format nil "~A~{~A~^, ~}"
                                              (bold-white "Exits: ")
                                              (mapcar #'yellow exits)))
          (player-send-message player "There are no exits here.")))))

(define-command "inventory" (world player args)
  (declare (ignore world args))
  (let ((inv (container-all-objects player)))
    (if (null inv)
        (player-send-message player "You are not carrying anything.")
        (player-send-message player 
                             (format nil "~A~%~{~A~%~}"
                                     (bold-white "You are carrying:")
                                     (mapcar (lambda (obj)
                                               (format nil "  - ~A" (object-describe obj)))
                                             inv))))))

(define-command "say" (world player args)
  (declare (ignore world))
  (let ((message args))
    (if (zerop (length message))
        (player-send-message player "Say what?")
        (let ((room (object-location player)))
          (player-send-message player (format nil "~A: ~A" (bold-white "You say") message))
          (loop for obj in (container-all-objects room) do
            (when (and (typep obj 'mud-character)
                       (not (eq obj player)))
              (player-send-message obj 
                                  (format nil "~A: ~A" 
                                          (bright-green (format nil "~A says" (object-name player))) message))))))))

(define-command "shout" (world player args)
  (let ((message args))
    (if (zerop (length message))
        (player-send-message player "Shout what? Usage: shout <message>")
        (progn
          (world-broadcast world
                           (format nil "~A: ~A" 
                                   (bold-red (format nil "~A shouts" (object-name player)))
                                   message)
                           player)
          (player-send-message player (format nil "~A: ~A" (bold-red "You shout") message))))))

(define-command "read" (world player args)
  (declare (ignore world))
  (let* ((room (object-location player))
         (guestbook (or (find-if (lambda (obj) (typep obj 'mud-guestbook)) (container-all-objects room))
                        (find-if (lambda (obj) (typep obj 'mud-guestbook)) (container-all-objects player)))))
    (cond
      ((and (not (zerop (length args)))
            (not (string-equal args "guestbook"))
            (not (search "guestbook" (string-downcase args))))
       (player-send-message player "Read what? Try: read guestbook"))
      ((null guestbook)
       (player-send-message player "There is nothing here to read."))
      (t
       (player-send-message player (guestbook-format-entries guestbook))))))

(define-command "write" (world player args)
  (declare (ignore world))
  (let* ((room (object-location player))
         (guestbook (or (find-if (lambda (obj) (typep obj 'mud-guestbook)) (container-all-objects room))
                        (find-if (lambda (obj) (typep obj 'mud-guestbook)) (container-all-objects player)))))
    (if (null guestbook)
        (player-send-message player "There is no guestbook here to write in.")
        (let* ((session (character-session player))
               (message (ask-input session "What message do you want to write?")))
          (if (zerop (length message))
              (player-send-message player "Write what? Please try again.")
              (progn
                (guestbook-add-entry guestbook (object-name player) message)
                (player-send-message player "You write your message in the guestbook.")
                (loop for obj in (container-all-objects room) do
                  (when (and (typep obj 'mud-character)
                             (not (eq obj player)))
                    (player-send-message obj (format nil "~A writes a message in ~A."
                                                     (object-name player)
                                                     (object-name guestbook)))))))))))

(define-command "help" (world player args)
  (declare (ignore world args))
  (let ((cmd-list (sort (loop for key being the hash-keys of *commands*
                              collect (cyan key))
                        #'string< :key #'string)))
    (player-send-message player
                         (format nil "~A~%~{~A~%~}~%Type 'help <command>' for more info."
                                 (bold-white "Available commands:")
                                 cmd-list))))

(define-command "toggle-colors" (world player args)
  (declare (ignore world args))
  (let* ((session (character-session player))
         (new-value (not (session-use-colors session))))
    (setf (session-use-colors session) new-value)
    ;; Rebinds *COLORIZE* to the new value so the response message
    ;; respects the toggle (process-command already bound it to the old value)
    (let ((*colorize* new-value))
      (player-send-message player
                           (format nil "Colors ~A."
                                   (if new-value
                                       (bright-green "enabled")
                                       (red "disabled")))))))

(define-command "quit" (world player args)
  (declare (ignore args))
  (player-send-message player "Goodbye!")
  (world-remove-character! world player)
  (session-disconnect (character-session player)))

;; ─── Speech handling ──────────────────────────────────────────────────────
;; Objects can implement HANDLE-SPEECH to respond when spoken/told to.

(defgeneric handle-speech (object speaker message)
  (:documentation "Called when SPEAKER directs MESSAGE at OBJECT.
  Returns non-NIL if the speech was handled, NIL otherwise.")
  (:method (object speaker message)
    (declare (ignore object speaker message))
    nil))

(define-command "tell" (world player args)
  (declare (ignore world))
  (if (zerop (length args))
      (player-send-message player "Tell who what? Usage: tell <name> <message>")
      (let* ((space-pos (position #\Space args))
             (target-name (if space-pos
                              (string-downcase (subseq args 0 space-pos))
                              (string-downcase args)))
             (message (if space-pos
                          (string-trim '(#\Space #\Tab) (subseq args (1+ space-pos)))
                          "")))
        (if (zerop (length message))
            (player-send-message player "Tell who what? Usage: tell <name> <message>")
            (let* ((room (object-location player))
                   (target (find-if (lambda (obj)
                                      (and (not (eq obj player))
                                           (or (search target-name (string-downcase (object-name obj)))
                                               (some (lambda (alias)
                                                       (string-equal target-name alias))
                                                     (object-aliases obj)))))
                                    (container-all-objects room))))
              (cond
                ((null target)
                 (player-send-message player (format nil "There's no ~A here to tell that to." args)))
                ((typep target 'mud-character)
                 ;; Send private message to another player
                 (player-send-message player (format nil "~A ~A ~A" (bold-white "You tell") (bright-green (format nil "~A:" (object-name target))) message))
                 (player-send-message target (format nil "~A ~A ~A" (bright-green (format nil "~A tells you" (object-name player))) (bold-white "privately:") message)))
                (t
                 ;; Tell an object — give it a chance to handle the speech
                 (player-send-message player (format nil "~A ~A ~A" (bold-white "You tell") (cyan (format nil "~A:" (object-name target))) message))
                 (unless (handle-speech target player message)
                   ;; Object didn't respond
                   (player-send-message player (format nil "~A doesn't seem to understand." (object-name target)))))))))))

(defun parse-command (input)
  "Parse a command string into command name and raw args string.
   Returns: (values command-name raw-args-string)"
  (let ((trimmed (string-trim '(#\Space #\Tab) input)))
    (if (zerop (length trimmed))
        (values nil "")
        (let ((space-pos (position #\Space trimmed)))
          (if space-pos
              (values (string-downcase (subseq trimmed 0 space-pos))
                      (string-trim '(#\Space #\Tab) (subseq trimmed (1+ space-pos))))
              (values (string-downcase trimmed) ""))))))

(defun process-command (world player command-string)
  "Process a command from a player.
Honors the player's session color preference by binding *COLORIZE*."
  ;; Issue an event for every line of player input (for debugging/logging).
  (let ((session (character-session player)))
    (issue-player-input-event (session-id session)
                              (object-name player)
                              command-string))
  
  (when (> (length command-string) +max-command-length+)
    (player-send-message player "Command too long.")
    (return-from process-command nil))
  
  (multiple-value-bind (command args) (parse-command command-string)
    (if (not command)
        (return-from process-command nil))
    
    (let ((handler (gethash command *commands*)))
      (if handler
          (let ((*colorize* (session-use-colors (character-session player))))
            (handler-case
                (funcall handler world player args)
              (error (e)
                (log-error "Command error for ~A: ~A" (object-name player) e)
                (player-send-message player "Error executing command."))))
          (player-send-message player "Unknown command. Type 'help' for available commands.")))))
