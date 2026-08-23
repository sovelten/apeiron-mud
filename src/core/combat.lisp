;;;; src/core/combat.lisp — Character combat system

(in-package #:apeiron.core)

(defconstant +character-default-hp+ 30)
(defconstant +character-default-attack-min+ 4)
(defconstant +character-default-attack-max+ 9)

(defun character-hp (character)
  (or (object-get-property character "hp") +character-default-hp+))

(defun character-max-hp (character)
  (or (object-get-property character "max-hp") +character-default-hp+))

(defun (setf character-hp) (value character)
  (object-set-property character "hp" (max 0 value)))

(defun character-ensure-combat-stats (character)
  (unless (object-get-property character "max-hp")
    (object-set-property character "max-hp" +character-default-hp+))
  (unless (object-get-property character "hp")
    (object-set-property character "hp" (character-max-hp character))))

(defun character-roll-attack (character)
  (declare (ignore character))
  (+ +character-default-attack-min+
     (random (1+ (- +character-default-attack-max+ +character-default-attack-min+)))))

(defun character-defeated-p (character)
  (<= (character-hp character) 0))

(defun character-heal-full (character)
  (setf (character-hp character) (character-max-hp character)))

(defun combat-attack-npc (world character npc)
  "Character attacks an NPC. Returns messages to send to the character."
  (character-ensure-combat-stats character)
  (let ((messages (list)))
    (when (npc-defeated-p npc)
      (return-from combat-attack-npc
        (list (format nil "~A is already defeated." (bold-red (object-name npc))))))
    (let ((damage (character-roll-attack character)))
      (setf (npc-hp npc) (- (npc-hp npc) damage))
      (push (format nil "~A ~A for ~A!"
                    (bold-green "You strike")
                    (bold-red (object-name npc))
                    (bold-red (format nil "~D damage" damage)))
            messages)
      (if (<= (npc-hp npc) 0)
          (progn
            (npc-defeat! npc)
            (push (bright-green (npc-defeat-message npc)) messages)
            (when (npc-victory-flag npc)
              (object-set-property character (npc-victory-flag npc) t)
              (push (format nil "~A ~A." (bright-yellow "You earned a victory mark:")
                            (bright-cyan (npc-victory-flag npc)))
                    messages)))
          (let ((counter (npc-roll-attack npc)))
            (setf (character-hp character) (- (character-hp character) counter))
            (push (format nil "~A hits you for ~A! (Your HP: ~A)"
                          (bold-red (object-name npc))
                          (bold-red (format nil "~D damage" counter))
                          (let ((hp-text (format nil "~D/~D"
                                                  (character-hp character)
                                                  (character-max-hp character))))
                            (if (<= (character-hp character) (/ (character-max-hp character) 4))
                                (bold-red hp-text)
                                (if (<= (character-hp character) (/ (character-max-hp character) 2))
                                    (yellow hp-text)
                                    (bright-green hp-text)))))
                  messages)
            (when (character-defeated-p character)
              (push (bold-red "You black out and wake up at the cavern entrance, bruised but alive.")
                    messages)
              (character-heal-full character)
              (let ((entrance (loop for r being the hash-values of (world-rooms world)
                                   when (search "Cavern Mouth" (object-name r))
                                   return r)))
                (when entrance
                  (object-move character entrance)))))))
    (nreverse messages)))
