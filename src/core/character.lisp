(in-package #:apeiron.core)

;; TODO: split character and player-character for building NPCs

(defclass mud-character (mud-object container-mixin)
  ((session :initarg :session
            :accessor character-session
            :initform nil
            :documentation "The session controlling this character"))
  (:documentation "A player character in the MUD"))

(defun new-character (name session)
  (let ((character (make-instance 'mud-character
                                  :id (make-id)
                                  :name name
                                  
                                  :session session)))
    ;; Link player to session
    (setf (session-character session) character)
    character))

(defun player-send-message (player message &key (newline t))
  "Send a message to a player. If NEWLINE is nil, don't add a trailing newline.
Honors the session's color preference by binding *COLORIZE* around the write."
  (let ((session (character-session player)))
    (let ((*colorize* (session-use-colors session)))
      (mud-write session message :newline newline))))
