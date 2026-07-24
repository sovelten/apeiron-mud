(in-package #:apeiron-test)

(in-suite core-suite)

(test container-objects-matching-exact-name
  "Test finding objects by exact name match"
  (let ((container (make-instance 'apeiron.core:mud-room
                                  :name "Test Container"))
        (obj1 (make-instance 'apeiron.core:mud-object :name "Sword" :id 1))
        (obj2 (make-instance 'apeiron.core:mud-object :name "Shield" :id 2))
        (obj3 (make-instance 'apeiron.core:mud-object :name "Potion" :id 3)))
    (apeiron.core:container-add-object container obj1)
    (apeiron.core:container-add-object container obj2)
    (apeiron.core:container-add-object container obj3)
    (let ((results (apeiron.core:container-objects-matching container "Sword")))
      (is (= 1 (length results)))
      (is (eq obj1 (first results))))
    (let ((results (apeiron.core:container-objects-matching container "Shield")))
      (is (= 1 (length results)))
      (is (eq obj2 (first results))))))

(test container-objects-matching-case-insensitive
  "Test that name matching is case-insensitive"
  (let ((container (make-instance 'apeiron.core:mud-room
                                  :name "Test Container"))
        (obj (make-instance 'apeiron.core:mud-object :name "Sword" :id 1)))
    (apeiron.core:container-add-object container obj)
    (is (= 1 (length (apeiron.core:container-objects-matching container "sword"))))
    (is (= 1 (length (apeiron.core:container-objects-matching container "SWORD"))))
    (is (= 1 (length (apeiron.core:container-objects-matching container "sWoRd"))))))

(test container-objects-matching-by-alias
  "Test finding objects by alias match"
  (let ((container (make-instance 'apeiron.core:mud-room
                                  :name "Test Container"))
        (obj (make-instance 'apeiron.core:mud-object
                            :name "Long Sword of Destiny"
                            :id 1
                            :aliases '("sword" "blade" "destiny"))))
    (apeiron.core:container-add-object container obj)
    (is (= 1 (length (apeiron.core:container-objects-matching container "sword"))))
    (is (= 1 (length (apeiron.core:container-objects-matching container "blade"))))
    (is (= 1 (length (apeiron.core:container-objects-matching container "destiny"))))
    ;; Full name should still work
    (is (= 1 (length (apeiron.core:container-objects-matching container "Long Sword of Destiny"))))))

(test container-objects-matching-no-match
  "Test that non-matching names return an empty list"
  (let ((container (make-instance 'apeiron.core:mud-room
                                  :name "Test Container"))
        (obj (make-instance 'apeiron.core:mud-object :name "Sword" :id 1)))
    (apeiron.core:container-add-object container obj)
    (is (null (apeiron.core:container-objects-matching container "Axe")))
    (is (null (apeiron.core:container-objects-matching container "")))))

(test container-objects-matching-empty-container
  "Test that an empty container returns an empty list"
  (let ((container (make-instance 'apeiron.core:mud-room
                                  :name "Empty Room")))
    (is (null (apeiron.core:container-objects-matching container "anything")))))

(test container-objects-matching-multiple-matches
  "Test that multiple matching objects are all returned"
  (let ((container (make-instance 'apeiron.core:mud-room
                                  :name "Test Container"))
        (sword1 (make-instance 'apeiron.core:mud-object
                               :name "Rusty Sword"
                               :id 1
                               :aliases '("sword")))
        (sword2 (make-instance 'apeiron.core:mud-object
                               :name "Iron Sword"
                               :id 2
                               :aliases '("sword")))
        (shield (make-instance 'apeiron.core:mud-object
                               :name "Iron Shield"
                               :id 3)))
    (apeiron.core:container-add-object container sword1)
    (apeiron.core:container-add-object container sword2)
    (apeiron.core:container-add-object container shield)
    (let ((results (apeiron.core:container-objects-matching container "sword")))
      (is (= 2 (length results)))
      (is (find sword1 results))
      (is (find sword2 results))
      (is (not (find shield results))))))

(test container-objects-matching-substring
  "Test that partial names match via whole-word search"
  (let ((container (make-instance 'apeiron.core:mud-room
                                  :name "Test Container"))
        (diary (make-instance 'apeiron.core:mud-object
                              :name "a worn leather diary"
                              :id 1))
        (sword (make-instance 'apeiron.core:mud-object
                              :name "Rusty Sword"
                              :id 2)))
    (apeiron.core:container-add-object container diary)
    (apeiron.core:container-add-object container sword)
    ;; Whole-word matching
    (is (= 1 (length (apeiron.core:container-objects-matching container "diary"))))
    (is (eq diary (first (apeiron.core:container-objects-matching container "diary"))))
    (is (= 1 (length (apeiron.core:container-objects-matching container "worn"))))
    (is (= 1 (length (apeiron.core:container-objects-matching container "sword"))))
    (is (eq sword (first (apeiron.core:container-objects-matching container "sword"))))
    (is (= 1 (length (apeiron.core:container-objects-matching container "Rusty"))))
    ;; Partial substrings of a word do NOT match
    (is (null (apeiron.core:container-objects-matching container "eath")))
    (is (null (apeiron.core:container-objects-matching container "usty")))
    ;; Case-insensitive whole word
    (is (= 1 (length (apeiron.core:container-objects-matching container "DIARY"))))))
