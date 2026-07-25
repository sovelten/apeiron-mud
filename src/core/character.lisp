(in-package #:apeiron.core)

;; TODO: split character and player-character for building NPCs

(defclass mud-character (mud-object container-mixin)
  ((session :initarg :session
            :accessor character-session
            :initform nil
            :documentation "The session controlling this character")
   (owner :initarg :owner
          :accessor character-owner
          :initform nil
          :documentation "The name of the mud-account that owns this character.
NIL for guest characters."))
  (:documentation "A character character in the MUD"))

(defun new-character (name session &key owner)
  (let ((character (make-instance 'mud-character
                                  :id (make-id)
                                  :name name
                                  :session session
                                  :owner owner)))
    ;; Link character to session
    (setf (session-character session) character)
    ;; Link account to character (bidirectional)
    (when owner
      (setf (account-character owner) character))
    character))

(defun character-send-message (character message &key (newline t))
  "Send a message to a character. If NEWLINE is nil, don't add a trailing newline.
Honors the session's color preference by binding *COLORIZE* around the write."
  (let ((session (character-session character)))
    (let ((*colorize* (session-use-colors session)))
      (mud-write session message :newline newline))))

(defmethod object-describe ((obj mud-character))
  "Bright green for character characters."
  (bright-green (format nil "~A (ID: ~D)" (object-name obj) (object-id obj))))
