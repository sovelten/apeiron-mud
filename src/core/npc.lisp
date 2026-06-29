;;;; src/core/npc.lisp — NPC (non-player character) definitions

(in-package #:apeiron.core)

(defclass mud-npc (mud-object)
  ((hp :initarg :hp
       :accessor npc-hp
       :documentation "Current hit points")
   (max-hp :initarg :max-hp
           :accessor npc-max-hp
           :documentation "Maximum hit points")
   (attack-min :initarg :attack-min
               :accessor npc-attack-min
               :initform 2
               :documentation "Minimum damage per attack")
   (attack-max :initarg :attack-max
               :accessor npc-attack-max
               :initform 5
               :documentation "Maximum damage per attack")
   (defeated :initarg :defeated
             :accessor npc-defeated-p
             :initform nil
             :documentation "Whether this NPC has been defeated")
   (defeat-message :initarg :defeat-message
                   :accessor npc-defeat-message
                   :initform "The foe collapses!"
                   :documentation "Message shown when the NPC is defeated")
   (victory-flag :initarg :victory-flag
                 :accessor npc-victory-flag
                 :initform nil
                 :documentation "Player property key set when this NPC is defeated"))
  (:documentation "A non-player character that can be fought in the MUD"))

(defun new-npc (&key name description hp max-hp attack-min attack-max
                      defeat-message victory-flag)
  "Create a new NPC."
  (let ((max-hp (or max-hp hp 10)))
    (make-instance 'mud-npc
                   :name name
                   :description description
                   :type +object-type-character+
                   :hp (or hp max-hp)
                   :max-hp max-hp
                   :attack-min attack-min
                   :attack-max attack-max
                   :defeat-message defeat-message
                   :victory-flag victory-flag)))

(defun npc-roll-attack (npc)
  (+ (npc-attack-min npc)
     (random (1+ (- (npc-attack-max npc) (npc-attack-min npc))))))

(defun npc-defeat! (npc)
  "Mark an NPC as defeated."
  (setf (npc-defeated-p npc) t
        (npc-hp npc) 0))

(defun find-npc-in-room (room name)
  "Find a living NPC in a room by partial name match."
  (find-if (lambda (obj)
             (and (typep obj 'mud-npc)
                  (not (npc-defeated-p obj))
                  (search (string-downcase name)
                          (string-downcase (object-name obj)))))
           (container-all-objects room)))

(defun npc-describe (npc)
  "Describe an NPC for examine/inventory output."
  (if (npc-defeated-p npc)
      (format nil "~A (defeated)" (object-name npc))
      (format nil "~A ~A — ~A"
              (bold-red (object-name npc))
              (yellow (format nil "[HP: ~D/~D]" (npc-hp npc) (npc-max-hp npc)))
              (object-description npc))))
