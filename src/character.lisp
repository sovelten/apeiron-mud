(in-package #:mud)

;; Player class - a specialized mud-object with network connection

(defclass mud-character (mud-object)
  ((session :initarg :session
            :accessor player-session
            :initform nil
            :documentation "The session controlling this player")
   (inventory :initarg :inventory
              :accessor player-inventory
              :initform (make-array 0 :adjustable t :fill-pointer t)
              :documentation "Items the player carries"))
  (:documentation "A player character in the MUD"))

(defun create-character (name session)
  (let ((character (make-instance 'mud-character
                                  :id (mud.utils:make-id)
                                  :name name
                                  :type +object-type-character+
                                  :session session
                                  :location *start-room*)))
    ;; Link player to session
    (setf (session-character session) character)
    character))

(defun player-inventory-add (player obj)
  "Add an object to a player's inventory."
  (vector-push-extend obj (player-inventory player)))

(defun player-inventory-remove (player obj)
  "Remove an object from a player's inventory."
  (setf (player-inventory player)
        (delete obj (player-inventory player))))

(defun player-send-message (player message &key (newline t))
  "Send a message to a player. If NEWLINE is nil, don't add a trailing newline."
  (let ((session (player-session player)))
    (session-send-message session message)))

(defun player-send-prompt (player)
  "Send a prompt to a player on the same line (no newline)."
  (player-send-message player "> " :newline nil))

(defun player-disconnect (player)
  "Disconnect a player from the MUD."
  (mud.utils:log-message "Player ~A disconnecting" (object-name player))
  (let ((room (object-location player))
        (session (player-session player)))
    ;; Remove from room
    (when (typep room 'mud-room)
      (room-remove-object room player))
    ;; Remove from world
    (world-remove-player (object-id player))
    ;; Close socket if it exists
    (session-disconnect session)))
