(in-package #:mud)

(defclass mud-guestbook (mud-object)
  ((entries :initarg :entries
            :accessor guestbook-entries
            :initform '()
            :documentation "A list of plists containing guestbook entries, with keys :author, :message, and :timestamp."))
  (:documentation "A guestbook in which characters can read and write messages."))

(defun new-guestbook (&key (name "a dusty guestbook"))
  "Create a new guestbook object."
  (make-instance 'mud-guestbook
                 :id (mud.utils:make-id)
                 :name name
                 :type +object-type-item+))

(defun guestbook-add-entry (guestbook author message)
  "Add a new message to the guestbook."
  (let ((entry (list :author author :message message :timestamp (get-universal-time))))
    (setf (guestbook-entries guestbook)
          (append (guestbook-entries guestbook) (list entry)))))

(defun guestbook-format-entries (guestbook)
  "Format the guestbook entries as a readable string."
  (let ((entries (guestbook-entries guestbook)))
    (if (null entries)
        (format nil "=== ~A ===~%~%The guestbook is currently empty.~%" (object-name guestbook))
        (with-output-to-string (stream)
          (format stream "=== ~A ===~%~%" (object-name guestbook))
          (loop for entry in entries
                for author = (getf entry :author)
                for message = (getf entry :message)
                for timestamp = (getf entry :timestamp)
                do (multiple-value-bind (second minute hour date month year)
                       (decode-universal-time timestamp)
                     (format stream "[~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D] ~A wrote:~%  ~A~%~%"
                             year month date hour minute second
                             author message)))))))
