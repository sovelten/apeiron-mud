;;;; src/core/sign.lisp — Sign objects with a fixed readable message
;;;;
;;;; A sign is a simple MUD object that mixes in READABLE-MIXIN so a
;;;; character can `read` it and see a fixed message carved on it.

(in-package #:apeiron.core)

(defclass mud-sign (mud-object readable-mixin)
  ()
  (:documentation "A sign with a fixed message that characters can read.

Built on READABLE-MIXIN, so the HANDLE-READ method defined there displays
the message to any character that reads the sign."))

(defmethod object-short-description ((obj mud-sign))
  "Yellow for signs."
  (yellow (format nil "~A (ID: ~D)" (object-name obj) (object-id obj))))

(defun new-sign (&key (name "a wooden sign")
                      (description "A simple wooden sign with words carved into it.")
                      (message "Nothing is written here.")
                      (location nil)
                      (aliases nil)
                      (keywords nil))
  "Create a new sign with a fixed MESSAGE that characters can read."
  (make-instance 'mud-sign
                 :name name
                 :description description
                 :message message
                 :location location
                 :aliases aliases
                 :keywords keywords))
