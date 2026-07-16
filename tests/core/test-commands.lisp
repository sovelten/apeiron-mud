(in-package #:apeiron-test)

(in-suite core-suite)

(test command-processing-look
  "Test the look command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-character! world player)
      ;; The look command should work without crashing
      (apeiron.core:process-command world player "look")
      (is (not (null player))))))

(test command-processing-help
  "Test the help command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-character! world player)
      (apeiron.core:process-command world player "help")
      (is (not (null player))))))

(test command-processing-exits
  "Test the exits command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-character! world player)
      (apeiron.core:process-command world player "exits")
      (is (not (null player))))))

(test command-processing-inventory
  "Test the inventory command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-character! world player)
      (apeiron.core:process-command world player "inventory")
      (is (not (null player))))))

(test command-processing-go
  "Test the go command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-character! world player)
      (let ((start-room (apeiron.core:object-location player)))
        ;; Try to go north (should work from starting room)
        (apeiron.core:process-command world player "go north")
        ;; Player should have moved or stayed in same room
        (is (not (null (apeiron.core:object-location player))))))))

(test command-processing-direction-shorthands
  "Test n/s/e/w direction shorthand commands"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-character! world player)
      (let ((start-room (apeiron.core:object-location player)))
        ;; "n" should go north (same as "go north")
        (apeiron.core:process-command world player "n")
        (let ((after-north (apeiron.core:object-location player)))
          ;; Player may have moved (north from Gathering goes to forest)
          (is (not (null after-north))))
        ;; Move back to start
        (apeiron.core:process-command world player "s")
        (let ((after-south (apeiron.core:object-location player)))
          (is (not (null after-south))))
        ;; "e" should go east
        (apeiron.core:process-command world player "e")
        (let ((after-east (apeiron.core:object-location player)))
          (is (not (null after-east))))))))

(test command-processing-unknown
  "Test unknown command handling"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
      (apeiron.core:world-add-character! world player)
      ;; Unknown command should not crash
      (apeiron.core:process-command world player "blahblah")
      (is (not (null player))))))

(test command-processing-eval
  "Test the eval command"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
          (captured-messages '()))
      (apeiron.core:world-add-character! world player)
      (let ((original-send-message (fdefinition 'apeiron.core:player-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:player-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured-messages)))
               
               ;; Test 1: No arguments
               (setf captured-messages '())
               (apeiron.core:process-command world player "eval")
               (is (equal '("Eval what? Usage: eval <code>") captured-messages))
               
               ;; Test 2: Simple sum
               (setf captured-messages '())
               (apeiron.core:process-command world player "eval (+ 3 4)")
               (is (equal '("7") captured-messages))
               
               ;; Test 3: Error handling
               (setf captured-messages '())
               (apeiron.core:process-command world player "eval (/ 1 0)")
               (is (= 1 (length captured-messages)))
               (is (search "Error" (car captured-messages))))
                         (setf (fdefinition 'apeiron.core:player-send-message) original-send-message))))))

(test command-processing-shout
  "Test the shout command — broadcasts to all players."
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player1 (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                                                       :stream (make-string-output-stream)
                                                                       :use-colors nil)))
          (player2 (apeiron.core:new-character "Bob" (make-instance 'apeiron.core:stream-session
                                                                     :stream (make-string-output-stream)
                                                                     :use-colors nil)))
          (messages1 '())
          (messages2 '()))
      (apeiron.core:world-add-character! world player1)
      (apeiron.core:world-add-character! world player2)
      (let ((original-send-message (fdefinition 'apeiron.core:player-send-message)))
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:player-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore newline))
                       (cond
                         ((eq p player1) (push msg messages1))
                         ((eq p player2) (push msg messages2))
                         (t (push msg messages1)))))
               
               ;; Test 1: no message shows usage
               (setf messages1 '() messages2 '())
               (apeiron.core:process-command world player1 "shout")
               (is (equal '("Shout what? Usage: shout <message>") messages1))
               (is (null messages2))
               
               ;; Test 2: shout is broadcast to everyone except the shouter
               (setf messages1 '() messages2 '())
               (apeiron.core:process-command world player1 "shout Hello everyone!")
               ;; Player1 gets the "You shout" confirmation
               (is (search "You shout" (car messages1)))
               ;; Player2 gets the broadcast
               (is (search "Alice shouts: Hello everyone!" (car messages2))))
          (setf (fdefinition 'apeiron.core:player-send-message) original-send-message))))))

(test command-processing-examine
  "Test the examine command"
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                                                           :stream (make-string-output-stream)
                                                                           :use-colors nil)))
          (captured '()))
      (apeiron.core:world-add-character! world player)
      (let* ((room (apeiron.core:object-location player))
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
             (original-send-message (fdefinition 'apeiron.core:player-send-message)))
        (apeiron.core:container-add-object room sword)
        (apeiron.core:container-add-object room npc)
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:player-send-message)
                     (lambda (p msg &key newline)
                       (declare (ignore p newline))
                       (push msg captured)))
               
               ;; Test 1: No arguments
               (setf captured '())
               (apeiron.core:process-command world player "examine")
               (is (search "Examine what?" (first captured)))
               
               ;; Test 2: Examine a generic object
               (setf captured '())
               (apeiron.core:process-command world player "examine sword")
               (is (= 1 (length captured)))
               (is (search "Rusty Sword" (first captured)))
               
               ;; Test 3: Examine an NPC (should include HP)
               (setf captured '())
               (apeiron.core:process-command world player "examine goblin")
               (is (= 1 (length captured)))
               (is (search "Goblin" (first captured)))
               (is (search "HP" (first captured)))
               
               ;; Test 4: Examine something not present
               (setf captured '())
               (apeiron.core:process-command world player "examine dragon")
               (is (search "don't see that" (first captured)))
               
               ;; Test 5: Examine another player in the room
               (setf captured '())
               (let ((bob (apeiron.core:new-character "Bob" (make-instance 'apeiron.core:stream-session
                                                                             :stream (make-string-output-stream)
                                                                             :use-colors nil))))
                 (apeiron.core:world-add-character! world bob)
                 (apeiron.core:object-move bob room)
                 (apeiron.core:process-command world player "examine bob")
                 (is (= 1 (length captured)))
                 (is (search "Bob" (first captured)))))
          (setf (fdefinition 'apeiron.core:player-send-message) original-send-message))))))

(test command-processing-tell
  "Test the tell command — private messages between players and objects."
  (let ((world (apeiron.persistence:world-restore-or-initialize :force-new t)))
    (let ((alice (apeiron.core:new-character "Alice" (make-instance 'apeiron.core:stream-session
                                                                     :stream (make-string-output-stream)
                                                                     :use-colors nil)))
          (bob (apeiron.core:new-character "Bob" (make-instance 'apeiron.core:stream-session
                                                                 :stream (make-string-output-stream)
                                                                 :use-colors nil)))
          (msgs-alice '())
          (msgs-bob '()))
      (apeiron.core:world-add-character! world alice)
      (apeiron.core:world-add-character! world bob)
      (let* ((room (apeiron.core:object-location alice))
             (goblin (make-instance 'apeiron.core:mud-npc
                                    :name "Goblin"
                                    :id 200
                                    :description "A smelly goblin."
                                    :hp 10
                                    :max-hp 10))
             (original-send-message (fdefinition 'apeiron.core:player-send-message)))
        (apeiron.core:object-move bob room)
        (apeiron.core:container-add-object room goblin)
        (unwind-protect
             (progn
               (setf (fdefinition 'apeiron.core:player-send-message)
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

               ;; Test 4: Tell another player
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

          (setf (fdefinition 'apeiron.core:player-send-message) original-send-message))))))
