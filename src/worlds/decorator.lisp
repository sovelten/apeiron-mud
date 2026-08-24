;;;; src/worlds/decorator.lisp — The Decorator object
;;;;
;;;; A room object that lets players rename and re-describe the room it
;;;; occupies via the `tell` command:
;;;;
;;;;   tell decorator set name
;;;;   tell decorator set description
;;;;
;;;; Both trigger an interactive input prompt (the same ASK-INPUT flow the
;;;; guestbook uses for `write`), then update the room's name or
;;;; description in place.  The decorator lives in the worlds package (not
;;;; core) because it is a world-building convenience, not core game
;;;; logic.

(in-package #:apeiron.worlds)

(named-readtables:in-readtable pythonic-string-syntax)

(defsection @decorator (:title "The Decorator Object")
  """The decorator is a room object that lets players rename and
  re-describe the room it occupies.  Tell it 'set name' or
  'set description' and it prompts for the new value, like writing in a
  guestbook."""
  (new-decorator function))

;; ─── Class ──────────────────────────────────────────────────────────────────

(defclass mud-decorator (mud-object)
  ()
  (:documentation "A room object that can rename and re-describe the room it occupies."))

(defmethod object-describe ((obj mud-decorator))
  "Magenta for decorators, so they stand out from plain objects."
  (magenta (format nil "~A (ID: ~D)" (object-name obj) (object-id obj))))

(defun new-decorator (&key (name "a decorator") (location nil)
                      (description "") (aliases nil) (keywords nil))
  "Create a new decorator object that can rename and re-describe the
room it occupies when told to."
  (make-instance 'mud-decorator
                 :name name
                 :location location
                 :description description
                 :aliases aliases
                 :keywords keywords))

;; ─── Speech handling ────────────────────────────────────────────────────────

(defmethod handle-tell ((obj mud-decorator) speaker message)
  "Handle 'tell decorator set name' and 'tell decorator set description'.

Prompts the speaker for the new value (like writing in a guestbook) and
updates the room the decorator occupies.  Returns T when the speech was
handled, NIL otherwise."
  (let ((room (object-location obj)))
    (cond
      ((not (typep room 'mud-room))
       (character-send-message speaker "The decorator is not in a room it can decorate.")
       t)
      ((string-equal (string-trim '(#\Space #\Tab) message) "set name")
       (let* ((session (character-session speaker))
              (new-name (ask-input session "What should this room be called?")))
         (if (zerop (length new-name))
             (character-send-message speaker "The room keeps its current name.")
             (progn
               (setf (object-name room) new-name)
               (character-send-message
                speaker
                (format nil "You rename the room to ~A." (bold-white new-name)))
               (dolist (other (characters-in-room room))
                 (unless (eq other speaker)
                   (character-send-message
                    other
                    (format nil "~A renames the room to ~A."
                            (object-name speaker) (bold-white new-name))))))))
       t)
      ((string-equal (string-trim '(#\Space #\Tab) message) "set description")
       (let* ((session (character-session speaker))
              (new-description (ask-input session "Describe this room in your own words:")))
         (if (zerop (length new-description))
             (character-send-message speaker "The room keeps its current description.")
             (progn
               (setf (object-description room) new-description)
               (character-send-message
                speaker
                "You rewrite the room's description.")
               (dolist (other (characters-in-room room))
                 (unless (eq other speaker)
                   (character-send-message
                    other
                    (format nil "~A rewrites the room's description." (object-name speaker))))))))
       t)
      (t nil))))
