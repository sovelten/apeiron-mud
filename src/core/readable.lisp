(in-package #:apeiron.core)

(defclass readable-mixin ()
  ((message :initarg :message
            :accessor readable-message
            :initform nil
            :documentation "String that will be shown when character reads object"))
  (:documentation "Objects that contain a message which can be read
should (or could?) use this mixin"))

(defmethod handle-read ((obj readable-mixin) reader)
  "Display the object's readable message to the reader."
  (character-send-message reader (readable-message obj))
  t)
