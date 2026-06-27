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
        (player-send-message player (room-describe room))
        (player-send-message player "You are in a void!"))))

(define-command "go" (world player args)
  (declare (ignore world))
  (let ((direction args)
        (room (object-location player)))
    (if (zerop (length direction))
        (player-send-message player "Go where? Usage: go <direction>")
        (let ((block-msg (or (room-exit-blocked-p room player direction)
                             (room-challenge-blocked-p room player direction))))
          (if block-msg
              (player-send-message player block-msg)
              (let ((target-room (room-get-exit room direction)))
                (if target-room
                    (progn
                      (object-move player target-room)
                      (player-send-message player (format nil "You go ~A.~%" direction))
                      (player-send-message player (room-describe target-room)))
                    (player-send-message player "You can't go that way."))))))))

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
                                   (search target-name (string-downcase (object-name obj)))))
                            (room-contents room)))))
          (if target
              (player-send-message
               player
               (if (typep target 'mud-npc)
                   (npc-describe target)
                   (format nil "~A~%~A"
                           (object-name target)
                           (object-description target))))
              (player-send-message player "You don't see that here."))))))

(define-command "answer" (world player args)
  (declare (ignore world))
  (let ((room (object-location player)))
    (if (zerop (length args))
        (player-send-message player "Answer what? Usage: answer <text>")
        (let* ((expected (object-get-property room "challenge-answer"))
               (flag (object-get-property room "challenge-flag")))
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
  (player-send-message player
                       (format nil "HP: ~D/~D"
                               (player-hp player)
                               (player-max-hp player))))

(define-command "eval" (world player args)
  (declare (ignore world))
  (let ((code-str args))
    (if (zerop (length code-str))
        (player-send-message player "Eval what? Usage: eval <code>")
        (handler-case
            (let* ((form (read-from-string code-str))
                   (room (object-location player))
                   (result (eval form)))
              (loop for obj across (room-contents room) do
                (when (and (typep obj 'mud-character)
                           (not (eq obj player)))
                  (player-send-message obj (format nil "~A casts the spell: ~A" (object-name player) form))
                  (player-send-message obj (format nil "~A" result))))
              (player-send-message player (format nil "~A" result)))
          (error (e)
            (player-send-message player (format nil "Error: ~A" e)))))))

(define-command "exits" (world player args)
  (declare (ignore world args))
  (let ((room (object-location player)))
    (let ((exits (loop for key being the hash-keys of (room-exits room)
                       collect key)))
      (if exits
          (player-send-message player (format nil "Exits: ~{~A~^, ~}" exits))
          (player-send-message player "There are no exits here.")))))

(define-command "inventory" (world player args)
  (declare (ignore world args))
  (let ((inv (player-inventory player)))
    (if (zerop (length inv))
        (player-send-message player "You are not carrying anything.")
        (player-send-message player 
                             (format nil "You are carrying:~%~{  - ~A~%~}"
                                     (map 'list #'object-describe inv))))))

(define-command "say" (world player args)
  (declare (ignore world))
  (let ((message args))
    (if (zerop (length message))
        (player-send-message player "Say what?")
        (let ((room (object-location player)))
          (player-send-message player (format nil "You say: ~A" message))
          (loop for obj across (room-contents room) do
            (when (and (typep obj 'mud-character)
                       (not (eq obj player)))
              (player-send-message obj 
                                  (format nil "~A says: ~A" 
                                          (object-name player) message))))))))

(define-command "shout" (world player args)
  (let ((message args))
    (if (zerop (length message))
        (player-send-message player "Shout what? Usage: shout <message>")
        (progn
          (world-broadcast world
                           (format nil "~A shouts: ~A" (object-name player) message)
                           player)
          (player-send-message player (format nil "You shout: ~A" message))))))

(define-command "read" (world player args)
  (declare (ignore world))
  (let* ((room (object-location player))
         (guestbook (or (find-if (lambda (obj) (typep obj 'mud-guestbook)) (room-contents room))
                        (find-if (lambda (obj) (typep obj 'mud-guestbook)) (player-inventory player)))))
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
         (guestbook (or (find-if (lambda (obj) (typep obj 'mud-guestbook)) (room-contents room))
                        (find-if (lambda (obj) (typep obj 'mud-guestbook)) (player-inventory player)))))
    (if (null guestbook)
        (player-send-message player "There is no guestbook here to write in.")
        (let* ((session (character-session player))
               (message (ask-input session "What message do you want to write?")))
          (if (zerop (length message))
              (player-send-message player "Write what? Please try again.")
              (progn
                (guestbook-add-entry guestbook (object-name player) message)
                (player-send-message player "You write your message in the guestbook.")
                (loop for obj across (room-contents room) do
                  (when (and (typep obj 'mud-character)
                             (not (eq obj player)))
                    (player-send-message obj (format nil "~A writes a message in ~A."
                                                     (object-name player)
                                                     (object-name guestbook)))))))))))

(define-command "help" (world player args)
  (declare (ignore world args))
  (let ((help-text "Available commands:~%~{  ~A~%~}~%Type 'help <command>' for more info."))
    (player-send-message player 
                         (format nil help-text 
                                 (sort (loop for key being the hash-keys of *commands*
                                             collect key)
                                       #'string<)))))

(define-command "quit" (world player args)
  (declare (ignore args))
  (player-send-message player "Goodbye!")
  (world-remove-character! world player)
  (session-disconnect (character-session player)))

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
  "Process a command from a player."
  (when (> (length command-string) +max-command-length+)
    (player-send-message player "Command too long.")
    (return-from process-command nil))
  
  (multiple-value-bind (command args) (parse-command command-string)
    (if (not command)
        (return-from process-command nil))
    
    (let ((handler (gethash command *commands*)))
      (if handler
          (handler-case
              (funcall handler world player args)
            (error (e)
              (log-error "Command error for ~A: ~A" (object-name player) e)
              (player-send-message player "Error executing command.")))
          (player-send-message player "Unknown command. Type 'help' for available commands.")))))
