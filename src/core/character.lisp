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
          :documentation "The name (string) of the mud-account that owns this character.
NIL for guest characters.  Stored as a plain string so it survives
BKNR restarts without needing an object reference."))
  (:documentation "A character in the MUD"))

(defun new-character (name session &key owner)
  (let ((character (make-instance 'mud-character
                                  :name name
                                  :session session
                                  :owner owner)))
    ;; Link character to session (one-way: session knows its character)
    (setf (session-character session) character)
    character))

(defun character-send-message (character message &key (newline t))
  "Send a message to a character. If NEWLINE is nil, don't add a trailing newline.
Honors the session's color preference by binding *COLORIZE* around the write.
If the character has no session (e.g. disconnected), the message is silently dropped."
  (let ((session (character-session character)))
    (when session
      (let ((*colorize* (session-use-colors session)))
        (mud-write session message :newline newline)))))

(defun find-character-in-room (room character-name)
  "Find a character in a room by name."
  (loop for obj in (container-all-objects room)
        when (and (typep obj 'mud-character)
                  (string-equal (object-name obj) character-name))
        return obj))

(defmethod object-describe ((obj mud-character))
  "Bright green for character characters."
  (bright-green (format nil "~A (ID: ~D)" (object-name obj) (object-id obj))))

(defun guest? (character)
  (null (character-owner character)))
