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

(test object-copy-copies-attributes-and-resets-identity
  "OBJECT-COPY returns an independent copy with the same attributes but
resets identity: ID -1 and location NIL.  Properties are deep-copied so
the copy and original never share mutable state."
  (let ((original (make-instance 'apeiron.core:mud-object
                                 :name "Gold Coin"
                                 :description "A shiny gold coin."
                                 :aliases '("coin" "gold")
                                 :keywords '("coin")))
        (room (apeiron.core:new-room :name "Somewhere")))
    (apeiron.core:object-set-property original "value" 10)
    (setf (apeiron.core:object-id original) 42)
    (setf (apeiron.core:object-location original) room)
    (let ((copy (object-copy original)))
      (is (typep copy 'apeiron.core:mud-object))
      (is (not (eq original copy)))
      (is (equal "Gold Coin" (apeiron.core:object-name copy)))
      (is (equal "A shiny gold coin." (apeiron.core:object-description copy)))
      (is (equal '("coin" "gold") (apeiron.core:object-aliases copy)))
      (is (equal '("coin") (apeiron.core:object-keywords copy)))
      ;; Identity is reset: no world ID, no location.
      (is (= -1 (apeiron.core:object-id copy)))
      (is (null (apeiron.core:object-location copy)))
      ;; Original untouched.
      (is (= 42 (apeiron.core:object-id original)))
      (is (eq room (apeiron.core:object-location original)))
      ;; Properties copied but not shared.
      (is (equal 10 (apeiron.core:object-get-property copy "value")))
      (apeiron.core:object-set-property copy "value" 99)
      (is (equal 10 (apeiron.core:object-get-property original "value"))))))

(test object-copy-copies-npc-stat-block
  "OBJECT-COPY on an NPC copies the stat block (HP, attack range,
defeat message, victory flag) into a fresh NPC."
  (let ((guard (apeiron.core:new-npc
                :name "a cavern guard"
                :description "A burly guard."
                :hp 20 :max-hp 20
                :attack-min 4 :attack-max 8
                :defeat-message "The guard falls."
                :victory-flag "beat-guard-1")))
    (let ((copy (object-copy guard)))
      (is (typep copy 'apeiron.core:mud-npc))
      (is (not (eq guard copy)))
      (is (= 20 (apeiron.core:npc-hp copy)))
      (is (= 20 (apeiron.core:npc-max-hp copy)))
      (is (= 4 (apeiron.core:npc-attack-min copy)))
      (is (= 8 (apeiron.core:npc-attack-max copy)))
      (is (equal "The guard falls." (apeiron.core:npc-defeat-message copy)))
      (is (equal "beat-guard-1" (apeiron.core:npc-victory-flag copy)))
      (is (= -1 (apeiron.core:object-id copy)))
      (is (null (apeiron.core:object-location copy))))))
