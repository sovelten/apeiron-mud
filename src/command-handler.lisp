(in-package #:mud)

;; Command processor
(defvar *commands* (make-hash-table :test #'equal)
  "Hash table of command handlers")

(defmacro define-command (name (player args) &body body)
  "Define a command handler. ARGS is a raw string that the handler can parse as needed."
  `(setf (gethash ,name *commands*)
         (lambda (,player ,args)
           ,@body)))

;; Built-in commands

(define-command "look" (player args)
  (declare (ignore args))
  (let ((room (object-location player)))
    (if room
        (player-send-message player (room-describe room))
        (player-send-message player "You are in a void!"))))

(define-command "go" (player args)
  (let ((direction args)
        (room (object-location player)))
    (if (zerop (length direction))
        (player-send-message player "Go where? Usage: go <direction>")
        (let ((target-room (room-get-exit room direction)))
          (if target-room
              (progn
                (object-move player target-room)
                (player-send-message player (format nil "You go ~A.~%" direction))
                (player-send-message player (room-describe target-room)))
              (player-send-message player "You can't go that way."))))))

(define-command "eval" (player args)
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

(define-command "exits" (player args)
  (declare (ignore args))
  (let ((room (object-location player)))
    (let ((exits (loop for key being the hash-keys of (room-exits room)
                       collect key)))
      (if exits
          (player-send-message player (format nil "Exits: ~{~A~^, ~}" exits))
          (player-send-message player "There are no exits here.")))))

(define-command "inventory" (player args)
  (declare (ignore args))
  (let ((inv (player-inventory player)))
    (if (zerop (length inv))
        (player-send-message player "You are not carrying anything.")
        (player-send-message player 
                             (format nil "You are carrying:~%~{  - ~A~%~}"
                                     (map 'list #'object-describe inv))))))

(define-command "say" (player args)
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

(define-command "help" (player args)
  (declare (ignore args))
  (let ((help-text "Available commands:~%~{  ~A~%~}~%Type 'help <command>' for more info."))
    (player-send-message player 
                         (format nil help-text 
                                 (sort (loop for key being the hash-keys of *commands*
                                             collect key)
                                       #'string<)))))

(define-command "quit" (player args)
  (declare (ignore args))
  (player-send-message player "Goodbye!")
  (remove-character player)
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

(defun process-command (player command-string)
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
              (funcall handler player args)
            (error (e)
              (mud.utils:log-error "Command error for ~A: ~A" (object-name player) e)
              (player-send-message player "Error executing command.")))
          (player-send-message player "Unknown command. Type 'help' for available commands.")))))
