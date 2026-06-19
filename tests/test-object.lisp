(in-package #:mud-test)

(in-suite mud-tests)

(test object-creation
  "Test that we can create basic objects"
  (let ((obj (mud:new-object :name "Test Object")))
    (unwind-protect
         (progn
           (is (stringp (mud:object-describe obj)))
           (is (equal (mud:object-name obj) "Test Object")))
      (bknr.indices:destroy-object obj))))

(test object-properties
  "Test object property storage"
  (let ((obj (mud:new-object)))
    (unwind-protect
         (progn
           (mud:object-set-property obj "test-prop" "test-value")
           (is (equal (mud:object-get-property obj "test-prop") "test-value")))
      (bknr.indices:destroy-object obj))))

(test print-object-mud-object
      "Test print-object for mud-object"
      (let* ((obj (mud:new-object :name "Test Object"))
             (out (with-output-to-string (s) (print-object obj s))))
        (unwind-protect
             (is (string-equal (format nil "#<MUD:MUD-OBJECT Test Object (ID: ~D)>" (mud:object-id obj))
                               out))
          (bknr.indices:destroy-object obj))))

(test print-object-mud-room
  "Test print-object for mud-room"
  (let ((room (mud:new-room :name "Test Room")))
    (unwind-protect
         (is (string-equal
              (format nil "#<MUD:MUD-ROOM Test Room (ID: ~D)>" (mud:object-id room))
              (with-output-to-string (s) (print-object room s))))
      (bknr.indices:destroy-object room))))

(test object-indexing
  "Test that we can create basic objects"
  (let ((obj (mud:new-object :name "Test Object"))
        (obj2 (mud:new-object :name "Test Object 2")))
    (unwind-protect
         (progn
           (is (equal obj (first (mud:object-with-name "Test Object"))))
           (is (equal obj2 (first (mud:object-with-name "Test Object 2"))))
           (is (equal 2 (length (mud:all-objects)))))
      (bknr.indices:destroy-object obj)
      (bknr.indices:destroy-object obj2))))
