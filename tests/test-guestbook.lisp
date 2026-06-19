(in-package #:mud-test)

(in-suite mud-tests)

(test guestbook-creation-and-methods
  "Test that we can create a guestbook, add entries, and format them"
  (uiop:with-temporary-file (:pathname temp-file :type "csv")
    (let ((gb (mud::new-guestbook :name "test guestbook" :filepath (namestring temp-file))))
      (unwind-protect
           (progn
             (is (typep gb 'mud::mud-guestbook))
             (is (equal (mud:object-name gb) "test guestbook"))
             (is (null (mud::guestbook-entries gb)))
             
             ;; Test adding an entry
             (mud::guestbook-add-entry gb "Sophia" "Hello, MUD!")
             (let ((entries (mud::guestbook-entries gb)))
               (is (= (length entries) 1))
               (is (equal (getf (first entries) :author) "Sophia"))
               (is (equal (getf (first entries) :message) "Hello, MUD!"))
               (is (numberp (getf (first entries) :timestamp))))
             
             ;; Test formatted output
             (let ((formatted (mud::guestbook-format-entries gb)))
               (is (search "test guestbook" formatted))
               (is (search "Sophia wrote:" formatted))
               (is (search "Hello, MUD!" formatted))))
        (bknr.indices:destroy-object gb)))))
