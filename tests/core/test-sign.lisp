;;;; tests/core/test-sign.lisp — Tests for the sign object
;;;;
;;;; A sign is a MUD object that mixes in READABLE-MIXIN, so characters
;;;; can `read` it to see a fixed message.

(in-package #:apeiron-test)

(in-suite core-suite)

(defun make-test-reader (&key (name "Reader"))
  "Create a character with a capture stream session for reading signs."
  (apeiron.core:new-character
   name
   (make-instance 'apeiron.core:stream-session
                  :stream (make-string-output-stream)
                  :use-colors nil)))

(test new-sign-creates-readable-object
  "NEW-SIGN creates a sign carrying a fixed message."
  (let ((sign (apeiron.core:new-sign :name "a welcome sign"
                                     :message "Welcome to Apeiron!")))
    (is (typep sign 'apeiron.core:mud-sign))
    (is (typep sign 'apeiron.core:mud-object))
    (is (typep sign 'apeiron.core:readable-mixin))
    (is (equal (apeiron.core:object-name sign) "a welcome sign"))
    (is (equal (apeiron.core:readable-message sign) "Welcome to Apeiron!"))))

(test new-sign-defaults
  "NEW-SIGN works with only a message and provides sensible defaults."
  (let ((sign (apeiron.core:new-sign :message "Keep out")))
    (is (typep sign 'apeiron.core:mud-sign))
    (is (equal (apeiron.core:object-name sign) "a wooden sign"))
    (is (equal (apeiron.core:readable-message sign) "Keep out"))
    (is (null (apeiron.core:object-location sign)))))

(test sign-handle-read-displays-message
  "HANDLE-READ on a sign sends the fixed message to the reader."
  (let* ((character (make-test-reader))
         (sign (apeiron.core:new-sign :name "a sign"
                                      :message "Beware of the grue.")))
    (is (apeiron.core:handle-read sign character))
    (let ((out (get-output-stream-string (apeiron.core:session-stream
                                          (apeiron.core:character-session character)))))
      (is (search "Beware of the grue." out)))))

(test sign-handle-read-without-session
  "HANDLE-READ on a sign doesn't crash when the reader has no session."
  (let ((character (make-instance 'apeiron.core:mud-character
                                  :name "Ghost"
                                  :session nil))
        (sign (apeiron.core:new-sign :name "a sign"
                                     :message "Read me.")))
    (is (apeiron.core:handle-read sign character))))

(test sign-object-short-description
  "OBJECT-SHORT-DESCRIPTION on a sign returns a string naming the sign."
  (let ((sign (apeiron.core:new-sign :name "a trail marker" :message "North"))
        (reader (make-test-reader)))
    (declare (ignore reader))
    (is (stringp (apeiron.core:object-short-description sign)))
    (is (search "a trail marker" (apeiron.core:object-short-description sign)))))

(test sign-read-command-end-to-end
  "The `read` command shows the sign's message to a character in the room."
  (let* ((world (apeiron.core:new-world))
         (room (apeiron.core:new-room :name "Crossroads"))
         (sign (apeiron.core:new-sign :name "a wooden sign"
                                      :description "A tall wooden sign at the crossroads."
                                      :message "Danger: bridge out ahead."))
         (character (make-test-reader :name "Traveler")))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-add-object! world character)
    (apeiron.core:world-add-object! world sign)
    (apeiron.core:world-set-starting-room! world room)
    (apeiron.core:create-object! world character)
    (apeiron.core:place-character! world character)
    (apeiron.core:container-add-object room sign)
    (apeiron.core:process-command world character "read sign")
    (let ((out (get-output-stream-string (apeiron.core:session-stream
                                          (apeiron.core:character-session character)))))
      (is (search "Danger: bridge out ahead." out)))))
