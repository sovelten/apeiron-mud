(in-package #:apeiron-test)

(in-suite core-suite)

(test command-processing-look
  "Test the look command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      ;; The look command should work without crashing
      (apeiron.core:process-command world character "look")
      (is (not (null character))))))

(test command-processing-help
  "Test the help command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (apeiron.core:process-command world character "help")
      (is (not (null character))))))

(test command-processing-exits
  "Test the exits command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (apeiron.core:process-command world character "exits")
      (is (not (null character))))))

(test command-processing-inventory
  "Test the inventory command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (apeiron.core:process-command world character "inventory")
      (is (not (null character))))))

(test command-processing-go
  "Test the go command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((start-room (apeiron.core:object-location character)))
        ;; Try to go north (should work from starting room)
        (apeiron.core:process-command world character "go north")
        ;; Character should have moved or stayed in same room
        (is (not (null (apeiron.core:object-location character))))))))

(test command-processing-direction-shorthands
  "Test n/s/e/w direction shorthand commands"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((start-room (apeiron.core:object-location character)))
        ;; "n" should go north (same as "go north")
        (apeiron.core:process-command world character "n")
        (let ((after-north (apeiron.core:object-location character)))
          ;; Character may have moved (north from Gathering goes to forest)
          (is (not (null after-north))))
        ;; Move back to start
        (apeiron.core:process-command world character "s")
        (let ((after-south (apeiron.core:object-location character)))
          (is (not (null after-south))))
        ;; "e" should go east
        (apeiron.core:process-command world character "e")
        (let ((after-east (apeiron.core:object-location character)))
          (is (not (null after-east))))))))

(test command-processing-unknown
  "Test unknown command handling"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      ;; Unknown command should not crash
      (apeiron.core:process-command world character "blahblah")
      (is (not (null character))))))

(test command-processing-eval
  "Test the eval command"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
          (captured-messages '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured-messages)))
               
               ;; Test 1: No arguments
               (setf captured-messages '())
               (apeiron.core:process-command world character "eval")
               (is (equal '("Eval what? Usage: eval <code>") captured-messages))
               
               ;; Test 2: Simple sum
               (setf captured-messages '())
               (apeiron.core:process-command world character "eval (+ 3 4)")
               (is (equal '("7") captured-messages))
               
               ;; Test 3: Error handling
               (setf captured-messages '())
               (apeiron.core:process-command world character "eval (/ 1 0)")
               (is (= 1 (length captured-messages)))
               (is (search "Error" (car captured-messages))))
                         (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-shout
  "Test the shout command — broadcasts to all characters."
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((character1 (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                                                       :stream (make-string-output-stream)
                                                                       :use-colors nil)))
          (character2 (apeiron.core:new-character "Bob" (make-instance 'apeiron.core:stream-session
                                                                     :stream (make-string-output-stream)
                                                                     :use-colors nil)))
          (messages1 '())
          (messages2 '()))
      (apeiron.core:create-object! world character1)
      (apeiron.core:place-character! world character1)
      (apeiron.core:create-object! world character2)
      (apeiron.core:place-character! world character2)
      (let ((original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore newline))
                       (cond
                         ((eq p character1) (push msg messages1))
                         ((eq p character2) (push msg messages2))
                         (t (push msg messages1)))))
               
               ;; Test 1: no message shows usage
               (setf messages1 '() messages2 '())
               (apeiron.core:process-command world character1 "shout")
               (is (equal '("Shout what? Usage: shout <message>") messages1))
               (is (null messages2))
               
               ;; Test 2: shout is broadcast to everyone except the shouter
               (setf messages1 '() messages2 '())
               (apeiron.core:process-command world character1 "shout Hello everyone!")
               ;; Character1 gets the "You shout" confirmation
               (is (search "You shout" (car messages1)))
               ;; Character2 gets the broadcast
               (is (search "Alice shouts: Hello everyone!" (car messages2))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-examine
  "Test the examine command"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let* ((room (apeiron.core:object-location character))
             (sword (make-instance 'apeiron.core:mud-object
                                   :name "Rusty Sword"
                                   :id 100
                                   :description "A rusty old blade."
                                   :aliases '("sword" "rusty")))
             (npc (make-instance 'apeiron.core:mud-npc
                                 :name "Goblin"
                                 :id 101
                                 :description "A smelly goblin."
                                 :hp 10
                                 :max-hp 10))
             (original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (apeiron.core:container-add-object room sword)
        (apeiron.core:container-add-object room npc)
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               
               ;; Test 1: No arguments
               (setf captured '())
               (apeiron.core:process-command world character "examine")
               (is (search "Examine what?" (first captured)))
               
               ;; Test 2: Examine a generic object
               (setf captured '())
               (apeiron.core:process-command world character "examine sword")
               (is (= 1 (length captured)))
               (is (search "Rusty Sword" (first captured)))
               
               ;; Test 3: Examine an NPC (should include HP)
               (setf captured '())
               (apeiron.core:process-command world character "examine goblin")
               (is (= 1 (length captured)))
               (is (search "Goblin" (first captured)))
               (is (search "HP" (first captured)))
               
               ;; Test 4: Examine something not present
               (setf captured '())
               (apeiron.core:process-command world character "examine dragon")
               (is (search "don't see that" (first captured)))
               
               ;; Test 5: Examine another character in the room
               (setf captured '())
               (let ((bob (apeiron.core:new-character "Bob" (make-instance 'apeiron.core:stream-session
                                                                             :stream (make-string-output-stream)
                                                                             :use-colors nil))))
                 (apeiron.core:create-object! world bob)
      (apeiron.core:place-character! world bob)
                 (apeiron.core:object-move bob room)
                 (apeiron.core:process-command world character "examine bob")
                 (is (= 1 (length captured)))
                 (is (search "Bob" (first captured)))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-tell
  "Test the tell command — private messages between characters and objects."
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                                                     :stream (make-string-output-stream)
                                                                     :use-colors nil)))
          (bob (apeiron.core:new-character "Bob" (make-instance 'apeiron.core:stream-session
                                                                 :stream (make-string-output-stream)
                                                                 :use-colors nil)))
          (msgs-alice '())
          (msgs-bob '()))
      (apeiron.core:create-object! world alice)
      (apeiron.core:place-character! world alice)
      (apeiron.core:create-object! world bob)
      (apeiron.core:place-character! world bob)
      (let* ((room (apeiron.core:object-location alice))
             (goblin (make-instance 'apeiron.core:mud-npc
                                    :name "Goblin"
                                    :id 200
                                    :description "A smelly goblin."
                                    :hp 10
                                    :max-hp 10))
             (original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (apeiron.core:object-move bob room)
        (apeiron.core:container-add-object room goblin)
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore newline))
                       (cond
                         ((eq p alice) (push msg msgs-alice))
                         ((eq p bob) (push msg msgs-bob))
                         (t (push msg msgs-alice)))))

               ;; Test 1: No arguments — usage message
               (setf msgs-alice '() msgs-bob '())
               (apeiron.core:process-command world alice "tell")
               (is (search "Tell who what?" (first msgs-alice)))
               (is (null msgs-bob))

               ;; Test 2: Name only, no message — usage message
               (setf msgs-alice '() msgs-bob '())
               (apeiron.core:process-command world alice "tell bob")
               (is (search "Tell who what?" (first msgs-alice)))
               (is (null msgs-bob))

               ;; Test 3: Target not in room
               (setf msgs-alice '() msgs-bob '())
               (apeiron.core:process-command world alice "tell dragon hello")
               (is (search "here to tell that to" (first msgs-alice)))
               (is (null msgs-bob))

               ;; Test 4: Tell another character
               (setf msgs-alice '() msgs-bob '())
               (apeiron.core:process-command world alice "tell bob Hello there!")
               ;; Alice sees "You tell Bob: Hello there!"
               (is (search "You tell" (first msgs-alice)))
               (is (search "Bob" (first msgs-alice)))
               (is (search "Hello there!" (first msgs-alice)))
               ;; Bob sees "Alice tells you privately: Hello there!"
               (is (search "Alice tells you" (first msgs-bob)))
               (is (search "privately" (first msgs-bob)))
               (is (search "Hello there!" (first msgs-bob)))

               ;; Test 5: Tell an NPC that doesn't handle speech
               (setf msgs-alice '() msgs-bob '())
               (apeiron.core:process-command world alice "tell goblin Give me your gold!")
               ;; push prepends, so last message sent is first in list
               ;; "Goblin doesn't seem to understand." is sent first, then "You tell Goblin: ..."
               (is (= 2 (length msgs-alice)))
               (is (search "doesn't seem to understand" (first msgs-alice)))
               (is (search "You tell" (second msgs-alice)))
               (is (search "Goblin" (second msgs-alice)))
               (is (search "Give me your gold!" (second msgs-alice)))
               ;; Bob sees nothing
               (is (null msgs-bob)))

          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test guestbook-read-write-via-commands
  "Test writing to and reading from a guestbook via process-command"
  (let* ((world (apeiron.core:new-world))
         (room (apeiron.core:new-room :name "Library"))
         (guestbook (apeiron.core:new-guestbook :name "guestbook" :filepath nil))
         (output (make-string-output-stream))
         (input (make-string-input-stream "Hello MUD!"))
         (io (make-two-way-stream input output)))
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-add-object! world guestbook)
    (apeiron.core:world-set-starting-room! world room)
    (let ((character (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                                                       :stream io
                                                                       :use-colors nil))))
      (apeiron.core:world-add-object! world character)
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (apeiron.core:container-add-object room guestbook)
      ;; Write a message via process-command
      (apeiron.core:process-command world character "write guestbook")
      ;; Verify entry was recorded
      (let ((entries (apeiron.core:guestbook-entries guestbook)))
        (is (= 1 (length entries)))
        (is (equal "Alice" (getf (first entries) :author)))
        (is (equal "Hello MUD!" (getf (first entries) :message))))
      ;; Read back via process-command
      (apeiron.core:process-command world character "read guestbook")
      (let ((text (get-output-stream-string output)))
        (is (search "Hello MUD!" text))
        (is (search "Alice" text))))))

;; ─── Eval debug helper function tests ──────────────────────────────────────

(test eval-helper-d-direct
  "Test (d obj) directly — returns describe output as a string, does not print to *standard-output*"
  (let* ((obj (make-instance 'apeiron.core:mud-object
                             :name "Widget"
                             :id 5001
                             :description "A widget."))
         (result (d obj)))
    (is (stringp result))
    (is (plusp (length result)))
    (is (search "Widget" result))
    (is (search "MUD-OBJECT" result))))

(test eval-helper-slots-of-direct
  "Test (slots-of obj) directly — returns slot info as a string"
  (let* ((obj (make-instance 'apeiron.core:mud-object
                             :name "Widget"
                             :id 5002
                             :description "A widget."))
         (result (slots-of obj)))
    (is (stringp result))
    (is (plusp (length result)))
    (is (search "Widget" result))))

(test eval-helper-props-direct
  "Test (props obj) directly — returns properties as a string"
  (let* ((obj (make-instance 'apeiron.core:mud-object
                             :name "Widget"
                             :id 5003
                             :description "A widget."))
         (result (props obj)))
    ;; No properties set yet — should say "No properties"
    (is (stringp result))
    (is (search "No properties" result))
    ;; Now set a property and check again
    (apeiron.core:object-set-property obj "my-key" "my-val")
    (let ((result2 (props obj)))
      (is (stringp result2))
      (is (search "my-key" result2))
      (is (search "my-val" result2)))))

(test eval-helper-inv-direct
  "Test (inv container) directly — returns container contents as a string"
  (let* ((container (make-instance 'apeiron.core:mud-room
                                   :name "Chest"
                                   :id 5004))
         (sword (make-instance 'apeiron.core:mud-object
                               :name "Silver Sword"
                               :id 5005
                               :description "A shiny silver sword."))
         (result (inv container)))
    ;; Empty container
    (is (stringp result))
    (is (search "empty" result))
    ;; Add an object
    (apeiron.core:container-add-object container sword)
    (let ((result2 (inv container)))
      (is (stringp result2))
      (is (search "Silver Sword" result2)))))

(test eval-helper-loc-direct
  "Test (loc obj) directly — returns location chain as a string"
  (let* ((room (make-instance 'apeiron.core:mud-room
                              :name "Test Room"
                              :id 5006))
         (obj (make-instance 'apeiron.core:mud-object
                             :name "Test Object"
                             :id 5007
                             :location room))
         (result (loc obj)))
    (is (stringp result))
    (is (plusp (length result)))
    (is (search "Test Object" result))
    (is (search "Test Room" result))))

(test eval-helper-obj-type-direct
  "Test (obj-type obj) directly — returns type name as a string"
  (let* ((obj (make-instance 'apeiron.core:mud-object
                             :name "Foo"
                             :id 5008))
         (result (obj-type obj)))
    (is (stringp result))
    (is (search "MUD-OBJECT" result)))
  (let* ((char (make-instance 'apeiron.core:mud-character
                              :name "Hero"
                              :id 5009
                              :session (make-instance 'apeiron.core:stream-session
                                                       :stream (make-string-output-stream))))
         (result (obj-type char)))
    (is (stringp result))
    (is (search "MUD-CHARACTER" result))))

(test eval-helper-props-empty-direct
  "Test (props obj) on an object with no properties"
  (let* ((obj (make-instance 'apeiron.core:mud-object
                             :name "Empty Thing"
                             :id 5010
                             :description "Nothing special."))
         (result (props obj)))
    (is (stringp result))
    (is (search "No properties" result))))

(test eval-helper-d-nil-safe
  "Test that (d nil) doesn't crash"
  (let ((result (d nil)))
    (is (stringp result))))

(test eval-helper-slots-of-mud-character
  "Test (slots-of) on a mud-character"
  (let* ((session (make-instance 'apeiron.core:stream-session
                                 :stream (make-string-output-stream)))
         (char (make-instance 'apeiron.core:mud-character
                              :name "Sir Test"
                              :id 5011
                              :session session))
         (result (slots-of char)))
    (is (stringp result))
    (is (plusp (length result)))
    (is (search "Sir Test" result))
    (is (search "MUD-CHARACTER" result))))

(test command-processing-eval-d
  "Test the eval d helper — describe object returning a string"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               (setf captured '())
               (apeiron.core:process-command world character "eval (d (me))")
               (is (= 1 (length captured)))
               (is (search "TestCharacter" (first captured)))
               (is (search "PERSISTENT-CHARACTER" (first captured))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-eval-slots-of
  "Test the eval slots-of helper — describe slots returning a string"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               (setf captured '())
               (apeiron.core:process-command world character "eval (slots-of (me))")
               (is (= 1 (length captured)))
               (is (search "TestCharacter" (first captured))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-eval-props
  "Test the eval props helper — show object properties returning a string"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let* ((room (apeiron.core:object-location character))
             (original-send-message (fdefinition 'apeiron.core:character-send-message)))
        ;; Set a property on the character so props output has something to show
        (apeiron.core:object-set-property character "test-key" "test-value")
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               (setf captured '())
               (apeiron.core:process-command world character
                                             "eval (props (me))")
               (is (= 1 (length captured)))
               (is (search "test-key" (first captured)))
               (is (search "test-value" (first captured))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-eval-inv
  "Test the eval inv helper — show container contents returning a string"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let* ((room (apeiron.core:object-location character))
             (sword (make-instance 'apeiron.core:mud-object
                                   :name "Rusty Sword"
                                   :id 9002
                                   :description "A rusty old blade."))
             (original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (apeiron.core:container-add-object room sword)
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               (setf captured '())
               (apeiron.core:process-command world character "eval (inv (here))")
               (is (= 1 (length captured)))
               (is (search "Rusty Sword" (first captured))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-eval-loc
  "Test the eval loc helper — show location chain returning a string"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               (setf captured '())
               (apeiron.core:process-command world character "eval (loc (me))")
               (is (= 1 (length captured)))
               (is (search "TestCharacter" (first captured)))
               (is (search "PERSISTENT-CHARACTER" (first captured))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-eval-obj-type
  "Test the eval obj-type helper — show type name returning a string"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               (setf captured '())
               (apeiron.core:process-command world character "eval (obj-type (me))")
               (is (= 1 (length captured)))
               (is (search "PERSISTENT-CHARACTER" (first captured))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-help-specific
  "Test 'help <command>' shows the specific command's docstring"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               ;; Test help for a specific command
               (setf captured '())
               (apeiron.core:process-command world character "help look")
               (is (= 1 (length captured)))
               (is (search "Help for" (first captured)))
               (is (search "look" (first captured)))
               (is (search "Look around" (first captured)))
               ;; Test help for unknown command
               (setf captured '())
               (apeiron.core:process-command world character "help nonexistent")
               (is (= 1 (length captured)))
               (is (search "Unknown command" (first captured)))
               ;; Test help with no arguments shows the command list
               (setf captured '())
               (apeiron.core:process-command world character "help")
               (is (= 1 (length captured)))
               (is (search "Available commands" (first captured))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-help-for-help
  "Test 'help help' shows help's own docstring"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((character (apeiron.core:new-character "TestCharacter" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((original-send-message (fdefinition 'apeiron.core:character-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:character-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               (setf captured '())
               (apeiron.core:process-command world character "help help")
               (is (= 1 (length captured)))
               (is (search "help" (first captured)))
               (is (search "Help for" (first captured)))
               (is (search "show help" (first captured))))
          (setf (fdefinition 'apeiron.core:character-send-message) original-send-message))))))

(test command-processing-say-with-sessionless-character
  "Reproduces the bug: when a mud-character with NIL session is in the room
(e.g. after a reconnect race where the old session's cleanup wipes
character-session before displace-character! can run), the say command
would crash because character-send-message calls session-use-colors on NIL.

After the fix, character-send-message gracefully drops messages for
sessionless characters instead of crashing."
  (let* ((world (apeiron.core:new-world))
         (room (apeiron.core:new-room :name "Test Room"))
         (output (make-string-output-stream))
         (alice-session (make-instance 'apeiron.core:stream-session
                                       :stream output
                                       :use-colors nil))
         (alice (apeiron.core:new-character "Alice" alice-session))
         ;; Bob is a mud-character with NIL session — simulating the
         ;; state after a reconnect race where the old thread's cleanup
         ;; wiped character-session before world-remove-character! ran.
         (bob (make-instance 'apeiron.core:mud-character
                             :name "Bob"
                             :id 9999
                             :owner "bob-account"
                             :session nil)))
    ;; Set up the world
    (apeiron.core:world-add-object! world room)
    (apeiron.core:world-add-object! world alice)
    (apeiron.core:world-add-object! world bob)
    (apeiron.core:world-set-starting-room! world room)
    (apeiron.core:place-character! world alice)
    ;; Place Bob directly in the room with NIL session — mimics the
    ;; state after old cleanup sets (character-session bob) = nil but
    ;; before/without displace-character! removing him from the room.
    (setf (apeiron.core:object-location bob) room)
    (apeiron.core:container-add-object room bob)

    ;; This used to signal:
    ;;   There is no applicable method for SESSION-USE-COLORS when
    ;;   called with arguments (NIL)
    ;; After the fix it completes without error.
    (apeiron.core:process-command world alice "say Hello!")
    (let ((text (get-output-stream-string output)))
      (is (search "You say" text))
      (is (search "Hello!" text)))))
