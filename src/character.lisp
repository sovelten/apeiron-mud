(in-package #:mud)

;; TODO: split character and player-character for building NPCs
(defclass mud-character (mud-object)
  ((session :initarg :session
            :accessor character-session
            :initform nil
            :documentation "The session controlling this character")
   (inventory :initarg :inventory
              :accessor player-inventory
              :initform (make-array 0 :adjustable t :fill-pointer t)
              :documentation "Items the player carries"))
  (:documentation "A player character in the MUD"))

(defun new-character (name session)
  (let ((character (make-instance 'mud-character
                                  :id (mud.utils:make-id)
                                  :name name
                                  :type +object-type-character+
                                  :session session)))
    ;; Link player to session
    (setf (session-character session) character)
    character))

(defun character-inventory-add (player obj)
  "Add an object to a player's inventory."
  (let ((inventory (player-inventory player)))
    (unless (and (vectorp inventory) (array-has-fill-pointer-p inventory))
      (setf inventory (make-array (length inventory)
                                  :adjustable t
                                  :fill-pointer (length inventory)
                                  :initial-contents inventory))
      (setf (player-inventory player) inventory))
    (vector-push-extend obj inventory)))

(defun character-inventory-remove (player obj)
  "Remove an object from a player's inventory."
  (let ((inventory (player-inventory player)))
    (unless (and (vectorp inventory) (array-has-fill-pointer-p inventory))
      (setf inventory (make-array (length inventory)
                                  :adjustable t
                                  :fill-pointer (length inventory)
                                  :initial-contents inventory))
      (setf (player-inventory player) inventory))
    (setf (player-inventory player)
          (delete obj inventory))))

(defun player-send-message (player message &key (newline t))
  "Send a message to a player. If NEWLINE is nil, don't add a trailing newline."
  (let ((session (character-session player)))
    (session-send-message session message :newline newline)))
