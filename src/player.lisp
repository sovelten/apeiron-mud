(in-package #:mud)

;; Player class - a specialized mud-object with network connection
(defclass mud-player (mud-object)
  ((socket :initarg :socket
           :accessor player-socket
           :documentation "Network socket for this player")
   (inventory :initarg :inventory
              :accessor player-inventory
              :initform (make-array 0 :adjustable t :fill-pointer t)
              :documentation "Items the player carries")
   (input-buffer :initarg :input-buffer
                 :accessor player-input-buffer
                 :initform ""
                 :documentation "Accumulated input from the player"))
  (:documentation "A player character in the MUD"))

(defun create-player (name socket)
  "Create a new player."
  (let ((player (make-instance 'mud-player
                               :id (mud.utils:make-id)
                               :name name
                               :type +object-type-player+
                               :socket socket
                               :location *start-room*)))
    ;; Add player to starting room
    (when *start-room*
      (room-add-object *start-room* player))
    ;; Register player globally
    (world-add-player player)
    player))

(defun player-inventory-add (player obj)
  "Add an object to a player's inventory."
  (vector-push-extend obj (player-inventory player)))

(defun player-inventory-remove (player obj)
  "Remove an object from a player's inventory."
  (setf (player-inventory player)
        (delete obj (player-inventory player))))

(defun player-send-message (player message)
  "Send a message to a player."
  (handler-case
      (let ((stream (usocket:socket-stream (player-socket player))))
        (format stream "~A~%" message)
        (force-output stream))
    (error (e)
      (mud.utils:log-error "Failed to send message to player ~A: ~A" 
                          (object-name player) e))))

(defun player-send-prompt (player)
  "Send a prompt to a player."
  (player-send-message player "> "))

(defun player-set-input-buffer (player text)
  "Set the input buffer for a player."
  (setf (player-input-buffer player) text))

(defun player-get-input-buffer (player)
  "Get the input buffer for a player."
  (player-input-buffer player))

(defun player-clear-input-buffer (player)
  "Clear the input buffer for a player."
  (setf (player-input-buffer player) ""))

(defun player-disconnect (player)
  "Disconnect a player from the MUD."
  (mud.utils:log-message "Player ~A disconnecting" (object-name player))
  (let ((room (object-location player)))
    ;; Remove from room
    (when (typep room 'mud-room)
      (room-remove-object room player))
    ;; Remove from world
    (world-remove-player (object-id player))
    ;; Close socket
    (usocket:socket-close (player-socket player))))
