;;;; tests/core/test-equipment.lisp — Tests for wearing/holding items
;;;;
;;;; Covers the WEAR / UNEQUIP API on characters (head, left/right hands,
;;;; feet), keyword matching rules, describing worn items, the
;;;; wear/remove/get/drop commands, and persistence of worn items across
;;;; a store restart.

(in-package #:apeiron-test)

(in-suite core-suite)

(defun make-test-character (&key (name "Equipper"))
  "Create a plain character with a capture stream session for testing."
  (apeiron.core:new-character
   name
   (make-instance 'apeiron.core:stream-session
                  :stream (make-string-output-stream)
                  :use-colors nil)))

(defun make-hat (&key (name "a wizard hat"))
  "A head-wearable item."
  (apeiron.core:new-object
   :name name
   :description "A pointy hat."
   :keywords '("hat" "wizard")
   :aliases '("hat" "wizard hat")))

(defun make-sword (&key (name "a rusty sword"))
  "A hand-held weapon."
  (apeiron.core:new-object
   :name name
   :description "A battered blade."
   :keywords '("weapon" "sword")
   :aliases '("sword")))

(defun make-shoe (&key (name "a pair of boots"))
  "A foot-wearable item."
  (apeiron.core:new-object
   :name name
   :description "Sturdy leather boots."
   :keywords '("boot" "shoe")
   :aliases '("boots" "shoes")))

(defun give (character object)
  "Put OBJECT into CHARACTER's inventory."
  (apeiron.core:container-add-object character object))

(test wear-hat-on-head
  "A hat (keyword hat) is worn on the head automatically."
  (let ((char (make-test-character))
        (hat (make-hat)))
    (give char hat)
    (multiple-value-bind (limb reason) (apeiron.core:wear char hat)
      (is (eq reason :ok))
      (is (typep limb 'apeiron.core:limb))
      (is (string= "head" (apeiron.core:object-name limb)))
      (is (eq hat (apeiron.core:limb-item limb)))
      ;; Worn items leave the inventory
      (is (null (find hat (apeiron.core:container-all-objects char))))
      ;; ...but keep the character as their location
      (is (eq char (apeiron.core:object-location hat))))))

(test wear-sword-into-hand
  "A weapon (keyword weapon) is held in the left hand first."
  (let ((char (make-test-character))
        (sword (make-sword)))
    (give char sword)
    (multiple-value-bind (limb reason) (apeiron.core:wear char sword)
      (is (eq reason :ok))
      (is (typep limb 'apeiron.core:limb))
      (is (string= "left hand" (apeiron.core:object-name limb)))
      (is (eq sword (apeiron.core:limb-item limb))))))

(test wear-shoes-on-feet
  "A shoe (keyword boot/shoe) is worn on the feet."
  (let ((char (make-test-character))
        (boots (make-shoe)))
    (give char boots)
    ;; Auto-fit wears on the feet
    (multiple-value-bind (limb reason) (apeiron.core:wear char boots)
      (is (eq reason :ok))
      (is (typep limb 'apeiron.core:limb))
      (is (string= "feet" (apeiron.core:object-name limb)))
      (is (eq boots (apeiron.core:limb-item limb))))
    ;; A second pair cannot be worn while the feet are taken
    (let ((sandal (apeiron.core:new-object :name "a sandal"
                                           :keywords '("sandal"))))
      (give char sandal)
      (multiple-value-bind (limb reason) (apeiron.core:wear char sandal "feet")
        (is (eq reason :occupied))
        (is (eq boots (apeiron.core:limb-item limb)))))
    ;; A head item still doesn't fit the feet
    (multiple-value-bind (limb reason) (apeiron.core:wear char (make-hat) "feet")
      (is (typep limb 'apeiron.core:limb))
      (is (eq reason :keywords-dont-match)))))

(test wear-explicit-limb
  "Wearing on an explicit limb name works ('wear sword on right hand')."
  (let ((char (make-test-character))
        (sword (make-sword)))
    (give char sword)
    (multiple-value-bind (limb reason) (apeiron.core:wear char sword "right hand")
      (is (eq reason :ok))
      (is (string= "right hand" (apeiron.core:object-name limb)))
      (is (eq sword (apeiron.core:limb-item limb)))
      (is (null (apeiron.core:limb-item
                 (apeiron.core:find-limb-by-name char "left hand")))))))

(test wear-keyword-mismatch-rejected
  "An item whose keywords don't match a slot cannot be worn there."
  (let ((char (make-test-character))
        (apple (apeiron.core:new-object :name "an apple"
                                        :keywords '("food"))))
    (give char apple)
    ;; Auto-fit fails (no limb accepts "food")
    (multiple-value-bind (limb reason) (apeiron.core:wear char apple)
      (is (null limb))
      (is (eq reason :no-fitting-limb)))
    ;; Explicit limb also refuses the mismatched item, reporting the limb
    (multiple-value-bind (limb reason) (apeiron.core:wear char apple "head")
      (is (typep limb 'apeiron.core:limb))
      (is (eq reason :keywords-dont-match)))
    ;; The apple is still in the inventory
    (is (find apple (apeiron.core:container-all-objects char)))))

(test wear-no-keywords-rejected
  "An item with no keywords fits no slot."
  (let ((char (make-test-character))
        (pebble (apeiron.core:new-object :name "a pebble")))
    (give char pebble)
    (multiple-value-bind (limb reason) (apeiron.core:wear char pebble)
      (is (null limb))
      (is (eq reason :no-fitting-limb)))))

(test wear-occupied-limb
  "A second hat cannot be worn while the head is occupied; the occupied
limb is reported."
  (let ((char (make-test-character))
        (hat (make-hat))
        (other-hat (make-hat :name "a feathered cap")))
    (give char hat)
    (give char other-hat)
    (apeiron.core:wear char hat)
    (multiple-value-bind (limb reason) (apeiron.core:wear char other-hat)
      (is (typep limb 'apeiron.core:limb))
      (is (eq reason :occupied))
      (is (eq hat (apeiron.core:limb-item limb))))))

(test wear-not-in-inventory
  "Wearing an item you don't carry fails with :not-in-inventory."
  (let ((char (make-test-character))
        (hat (make-hat)))
    (multiple-value-bind (limb reason) (apeiron.core:wear char hat)
      (is (null limb))
      (is (eq reason :not-in-inventory)))))

(test wear-unknown-limb
  "Wearing on a limb the character doesn't have fails with :no-such-limb."
  (let ((char (make-test-character))
        (hat (make-hat)))
    (give char hat)
    (multiple-value-bind (limb reason) (apeiron.core:wear char hat "third hand")
      (is (null limb))
      (is (eq reason :no-such-limb)))))

(test unequip-returns-to-inventory
  "UNEQUIP moves a worn item back into the inventory."
  (let ((char (make-test-character))
        (hat (make-hat)))
    (give char hat)
    (apeiron.core:wear char hat)
    (multiple-value-bind (item limb) (apeiron.core:unequip char hat)
      (is (eq item hat))
      (is (typep limb 'apeiron.core:limb))
      (is (null (apeiron.core:limb-item limb)))
      (is (find hat (apeiron.core:container-all-objects char)))
      (is (eq char (apeiron.core:object-location hat))))))

(test unequip-not-equipped
  "UNEQUIP on an item that isn't equipped returns (nil nil)."
  (let ((char (make-test-character))
        (hat (make-hat)))
    (give char hat)
    (multiple-value-bind (item limb) (apeiron.core:unequip char hat)
      (is (null item))
      (is (null limb)))))

(test character-worn-items-listing
  "CHARACTER-WORN-ITEMS lists every equipped item with its limb."
  (let ((char (make-test-character))
        (hat (make-hat))
        (sword (make-sword)))
    (give char hat)
    (give char sword)
    (apeiron.core:wear char hat)
    (apeiron.core:wear char sword)
    (let ((worn (apeiron.core:character-worn-items char)))
      (is (= 2 (length worn)))
      (is (find hat worn :key #'cdr))
      (is (find sword worn :key #'cdr))
      (is (string= "head" (apeiron.core:object-name
                           (car (find hat worn :key #'cdr)))))
      (is (string= "left hand" (apeiron.core:object-name
                                (car (find sword worn :key #'cdr))))))))

(test describe-shows-worn-items
  "OBJECT-LONG-DESCRIPTION of a character lists worn/held items."
  (let ((char (make-test-character))
        (hat (make-hat)))
    (give char hat)
    (apeiron.core:wear char hat)
    (let ((text (apeiron.core:object-long-description char)))
      (is (search "Wearing/holding:" text))
      (is (search "wizard hat" (string-downcase text)))
      (is (search "head" (string-downcase text))))))

(test describe-plain-when-nothing-worn
  "OBJECT-LONG-DESCRIPTION of a bare character has no equipment section."
  (let ((char (make-test-character)))
    (let ((text (apeiron.core:object-long-description char)))
      (is (not (search "Wearing/holding:" text))))))

;; ─── Command-level tests ───────────────────────────────────────────────────

(defun make-command-world ()
  "A transient world with a single room containing a hat and a sword."
  (let* ((world (apeiron.core:new-world))
         (room (apeiron.core:new-room :name "Test Room")))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-set-starting-room! world room)
    (apeiron.core:container-add-object room (make-hat))
    (apeiron.core:container-add-object room (make-sword))
    world))

(test wear-remove-get-drop-commands
  "The wear/remove/get/drop commands work end to end."
  (let ((world (make-command-world)))
    (let ((character (make-test-character :name "Wearer")))
      (apeiron.core:world-add-object! world character)
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let* ((session (apeiron.core:character-session character))
             (room (apeiron.core:object-location character))
             (hat (first (apeiron.core:container-objects-matching room "hat"))))
        ;; get the hat from the room — it must leave the room
        (apeiron.core:process-command world character "get hat")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "pick up" out))
          (is (search "wizard hat" out)))
        (is (= 1 (length (apeiron.core:container-all-objects character))))
        (is (null (first (apeiron.core:container-objects-matching room "hat"))))
        ;; wear it — auto-fits the head
        (apeiron.core:process-command world character "wear hat")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "You wear a wizard hat on your head" out)))
        (is (not (null (apeiron.core:limb-item
                        (apeiron.core:find-limb-by-name character "head")))))
        ;; get the sword and hold it in a hand
        (apeiron.core:process-command world character "get sword")
        (apeiron.core:process-command world character "wear sword")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "hold a rusty sword in your left hand" out)))
        (is (not (null (apeiron.core:limb-item
                        (apeiron.core:find-limb-by-name character "left hand")))))
        ;; removing the hat returns it to the inventory
        (apeiron.core:process-command world character "remove hat")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "You remove a wizard hat from your head" out)))
        (is (null (apeiron.core:limb-item
                   (apeiron.core:find-limb-by-name character "head"))))
        (is (= 1 (length (apeiron.core:container-all-objects character))))
        ;; drop the hat (now in inventory) back into the room
        (apeiron.core:process-command world character "drop hat")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "You drop a wizard hat" out)))
        (is (eq hat (first (apeiron.core:container-objects-matching room "hat"))))
        ;; removing the sword clears the left hand
        (apeiron.core:process-command world character "remove sword")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "You remove a rusty sword from your left hand" out)))
        (is (null (apeiron.core:limb-item
                   (apeiron.core:find-limb-by-name character "left hand"))))
        ;; the room now holds exactly the hat (the sword is in inventory)
        (let ((room-objs (remove-if (lambda (o)
                                      (typep o 'apeiron.core:mud-character))
                                    (apeiron.core:container-all-objects room))))
          (is (= 1 (length room-objs)))
          (is (find hat room-objs)))))))

(test wear-command-rejects-mismatch
  "Wearing an item with the wrong keywords reports a clear message."
  (let ((world (make-command-world)))
    (let ((character (make-test-character :name "Wearer")))
      (apeiron.core:world-add-object! world character)
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((session (apeiron.core:character-session character))
            (room (apeiron.core:object-location character)))
        (apeiron.core:container-add-object room
                                          (apeiron.core:new-object
                                           :name "an apple"
                                           :keywords '("food")))
        (apeiron.core:process-command world character "get apple")
        (apeiron.core:process-command world character "wear apple")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "nothing fits" out)))
        (apeiron.core:process-command world character "wear apple on head")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "doesn't belong" out)))))))

(test wear-command-what-usage
  "The wear command with no argument shows usage."
  (let ((world (make-command-world)))
    (let ((character (make-test-character :name "Wearer")))
      (apeiron.core:world-add-object! world character)
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((session (apeiron.core:character-session character)))
        (apeiron.core:process-command world character "wear")
        (let ((out (get-output-stream-string (apeiron.core:session-stream session))))
          (is (search "Wear what?" out)))))))

;; ─── Persistence ────────────────────────────────────────────────────────────

(test worn-item-persists-across-restore
  "A worn item survives a BKNR store close/reopen on the character's head."
  (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
         (character (apeiron.core:new-character
                     "PersistWearer"
                     (make-instance 'apeiron.core:stream-session
                                    :stream (make-string-output-stream)
                                    :use-colors nil)
                     :owner "persist-wearer-owner"))
         (hat (make-hat)))
    (apeiron.core:create-object! world character)
    (apeiron.core:create-object! world hat)
    (apeiron.core:place-character! world character)
    (apeiron.core:container-add-object character hat)
    (multiple-value-bind (limb reason) (apeiron.core:wear character hat)
      (is (eq reason :ok))
      (is (string= "head" (apeiron.core:object-name limb))))
    (apeiron.persistence:sync-world)
    (bknr.datastore:close-store)
    ;; Restart
    (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
           (restored (apeiron.core:find-character-by-owner
                      new-world "persist-wearer-owner")))
      (is (not (null restored))
          "Owned character should survive the restart")
      (let ((worn (apeiron.core:character-worn-items restored)))
        (is (= 1 (length worn)))
        (is (string= "head" (apeiron.core:object-name (caar worn))))
        (is (search "wizard hat"
                    (string-downcase (apeiron.core:object-name (cdar worn)))))))))

(test guest-removal-drops-items-and-deletes-limbs
  "Removing a guest character drops worn and carried items into the room
and deletes the character's persistent limbs (no leaked store-objects)."
  (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
         (room (apeiron.core:starting-room world))
         (guest (apeiron.core:new-character
                 "GuestCleanup"
                 (make-instance 'apeiron.core:stream-session
                                :stream (make-string-output-stream)
                                :use-colors nil)))
         (hat (apeiron.core:new-object :name "a hat" :keywords '("hat")))
         (apple (apeiron.core:new-object :name "an apple")))
    (apeiron.core:create-object! world guest)
    (apeiron.core:create-object! world hat)
    (apeiron.core:create-object! world apple)
    (apeiron.core:place-character! world guest)
    (apeiron.core:container-add-object guest hat)
    (apeiron.core:container-add-object guest apple)
    (apeiron.core:wear guest hat)
    ;; Guest limbs are persistent store-objects
    (is (typep (first (apeiron.core:character-limbs guest))
               (find-class (find-symbol "PERSISTENT-LIMB" :apeiron.persistence))))
    ;; Remove the guest: drop items, delete character and limbs
    (apeiron.core:world-remove-character! world guest)
    ;; Character is gone from the room
    (is (null (apeiron.core:find-character-in-room room "GuestCleanup")))
    ;; Worn + carried items were dropped into the room
    (is (find hat (apeiron.core:container-all-objects room)))
    (is (find apple (apeiron.core:container-all-objects room)))
    ;; No persistent limb store-objects leaked
    (is (null (bknr.datastore:store-objects-with-class
               (find-symbol "PERSISTENT-LIMB" :apeiron.persistence))))))

(test default-world-has-starter-equipment
  "The default transient world starts with a wearable hat and a weapon."
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((room (apeiron.core:starting-room world)))
      (is (not (null (apeiron.core:container-objects-matching room "hat"))))
      (is (not (null (apeiron.core:container-objects-matching room "sword")))))))
