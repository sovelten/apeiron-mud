(in-package #:apeiron-test)

(in-suite core-suite)

(test object-creation
  "Test that we can create basic objects"
  (let ((obj (apeiron.core:new-object :name "Test Object")))
    (is (stringp (apeiron.core:object-short-description obj)))
    (is (equal (apeiron.core:object-name obj) "Test Object"))))

(test object-properties
  "Test object property storage"
  (let ((obj (apeiron.core:new-object)))
    (apeiron.core:object-set-property obj "test-prop" "test-value")
    (is (equal (apeiron.core:object-get-property obj "test-prop") "test-value"))))

(test add-keyword
  "Test add-keyword adds a keyword to an object"
  (let ((obj (apeiron.core:new-object)))
    (apeiron.core:add-keyword obj "sword")
    (is (equal (apeiron.core:object-keywords obj) '("sword")))
    (apeiron.core:add-keyword obj "shield")
    (is (equal (apeiron.core:object-keywords obj) '("shield" "sword")))))

(test add-keyword-ignores-duplicates
  "Test add-keyword ignores existing keywords, case-insensitively"
  (let ((obj (apeiron.core:new-object :keywords '("sword"))))
    (apeiron.core:add-keyword obj "sword")
    (apeiron.core:add-keyword obj "SWORD")
    (is (equal (apeiron.core:object-keywords obj) '("sword")))))

(test remove-keyword
  "Test remove-keyword removes a keyword from an object"
  (let ((obj (apeiron.core:new-object :keywords '("sword" "shield"))))
    (apeiron.core:remove-keyword obj "sword")
    (is (equal (apeiron.core:object-keywords obj) '("shield")))
    (apeiron.core:remove-keyword obj "shield")
    (is (null (apeiron.core:object-keywords obj)))))

(test remove-keyword-missing
  "Test remove-keyword is a no-op when the keyword is not present"
  (let ((obj (apeiron.core:new-object :keywords '("sword"))))
    (apeiron.core:remove-keyword obj "shield")
    (is (equal (apeiron.core:object-keywords obj) '("sword")))))

(test print-object-mud-object
      "Test print-object for mud-object"
      (let* ((obj (apeiron.core:new-object :name "Test Object"))
             (out (with-output-to-string (s) (print-object obj s))))
        (is (string-equal (format nil "#<MUD-OBJECT Test Object (ID: ~D)>" (apeiron.core:object-id obj))
                          out))))

(test print-object-mud-room
  "Test print-object for mud-room"
  (let ((room (apeiron.core:new-room :name "Test Room")))
    (is (string-equal
         (format nil "#<MUD-ROOM Test Room (ID: ~D)>" (apeiron.core:object-id room))
         (with-output-to-string (s) (print-object room s))))))

(test world-object-lookup
  "Test that objects registered in a world are findable via world-level queries"
  (let ((world (apeiron.core:new-world)))
    (let ((obj (apeiron.core:new-object :name "Test Object"))
          (obj2 (apeiron.core:new-object :name "Test Object 2")))
      (apeiron.core:world-add-object! world obj)
      (apeiron.core:world-add-object! world obj2)
      (is (equal obj (apeiron.core:world-object-by-id world (apeiron.core:object-id obj))))
      (is (equal obj2 (apeiron.core:world-object-with-name world "Test Object 2")))
      (is (= 2 (length (apeiron.core:world-all-objects world)))))))
