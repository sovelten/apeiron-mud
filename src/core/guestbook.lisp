(in-package #:apeiron.core)

(defclass mud-guestbook (mud-object)
  ((entries :initarg :entries
            :accessor guestbook-entries
            :initform '()
            :documentation "A list of plists containing guestbook entries, with keys :author, :message, and :timestamp.")
   (filepath :initarg :filepath
             :accessor guestbook-filepath
             :documentation "File where the guestbook entries will be stored"))
  (:documentation "A guestbook in which characters can read and write messages."))

(defmethod object-describe ((obj mud-guestbook))
  "Cyan for guestbooks."
  (cyan (format nil "~A (ID: ~D)" (object-name obj) (object-id obj))))

(defmethod handle-read ((obj mud-guestbook) reader)
  "Display the guestbook entries to the reader."
  (player-send-message reader (guestbook-format-entries obj))
  t)

(defmethod handle-write ((obj mud-guestbook) writer message)
  "Record a message in the guestbook and broadcast to the room."
  (guestbook-add-entry obj (object-name writer) message)
  (player-send-message writer "You write your message in the guestbook.")
  (let ((room (object-location writer)))
    (when room
      (loop for other in (container-all-objects room) do
        (when (and (typep other 'mud-character)
                   (not (eq other writer)))
          (player-send-message other (format nil "~A writes a message in ~A."
                                             (object-name writer)
                                             (object-name obj)))))))
  t)

(defun guestbook-load-from-csv (filepath)
  "Read a CSV file and return a list of entry plists."
  (when (probe-file filepath)
    (mapcar (lambda (row)
              (list :author    (first row)
                    :message   (second row)
                    :timestamp (parse-integer (third row))))
            (cl-csv:read-csv (pathname filepath)))))

(defun new-guestbook (&key (name "a dusty guestbook") (filepath nil filepath-supplied-p))
  (let* ((effective-filepath (if filepath-supplied-p
                                 filepath
                                 (namestring
                                  (merge-pathnames
                                   (make-pathname :name (substitute #\- #\space name)
                                                  :type "csv")
                                   *data-directory*))))
         (filepath-str (if (pathnamep effective-filepath)
                           (namestring effective-filepath)
                           effective-filepath))
         (gb (make-instance 'mud-guestbook
                            :name name
                            :filepath filepath-str)))
    (when filepath-str
      (log-message "Loading csv from ~A" filepath-str)
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
        (format nil "~A~%~%The guestbook is currently empty.~%"
                (bold-white (format nil "=== ~A ===" (object-name guestbook))))
        (with-output-to-string (stream)
          (format stream "~A~%~%"
                  (bold-white (format nil "=== ~A ===" (object-name guestbook))))
          (loop for entry in entries
                for author = (getf entry :author)
                for message = (getf entry :message)
                for timestamp = (getf entry :timestamp)
                do (multiple-value-bind (second minute hour date month year)
                       (decode-universal-time timestamp)
                     (format stream "[~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D] ~A wrote:~%  ~A~%~%"
                             year month date hour minute second
                             (bright-green author) message)))))))
