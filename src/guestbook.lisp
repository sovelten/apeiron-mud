(in-package #:mud)

(defclass mud-guestbook (mud-object)
  ((entries :initarg :entries
            :accessor guestbook-entries
            :initform '()
            :documentation "A list of plists containing guestbook entries, with keys :author, :message, and :timestamp.")
   (filepath :initarg :filepath
             :accessor guestbook-filepath
             :documentation "File where the guestbook entries will be stored"))
  (:metaclass bknr.indices:indexed-class)
  (:documentation "A guestbook in which characters can read and write messages."))

(defun guestbook-load-from-csv (filepath)
  "Read a CSV file and return a list of entry plists."
  (when (probe-file filepath)
    (mapcar (lambda (row)
              (list :author    (first row)
                    :message   (second row)
                    :timestamp (parse-integer (third row))))
            (cl-csv:read-csv (pathname filepath)))))

(defun new-guestbook (&key (name "a dusty guestbook") (filepath "./guestbook.csv"))
  (let* ((filepath-str (if (pathnamep filepath)
                           (namestring filepath)
                           filepath))
         (gb (make-instance 'mud-guestbook
                            :id (mud.utils:make-id)
                            :name name
                            :filepath filepath-str
                            :type +object-type-item+)))
    (when filepath-str
      (mud.utils:log-message "Loading csv from ~A" filepath-str)
      (setf (guestbook-entries gb)
            (guestbook-load-from-csv (pathname filepath-str))))
    gb))

(defun guestbook-append-entry-to-csv (entry filepath)
  (with-open-file (stream filepath
                          :direction :output
                          :if-exists :append
                          :if-does-not-exist :create)
    (cl-csv:write-csv-row
      (list (getf entry :author)
            (getf entry :message)
            (write-to-string (getf entry :timestamp)))
      :stream stream)))

(defun guestbook-add-entry (guestbook author message)
  "Add a new message to the guestbook."
  (let ((entry (list :author author :message message :timestamp (get-universal-time))))
    (setf (guestbook-entries guestbook)
          (append (guestbook-entries guestbook) (list entry)))
    (guestbook-append-entry-to-csv entry (guestbook-filepath guestbook))))

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
