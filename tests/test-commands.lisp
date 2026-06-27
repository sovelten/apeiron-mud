(in-package #:mud-test)

(in-suite mud-tests)

(test command-processing-look
  "Test the look command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-add-character! world player)
      ;; The look command should work without crashing
      (apeiron.core:process-command world player "look")
      (is (not (null player))))))

(test command-processing-help
  "Test the help command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-add-character! world player)
      (apeiron.core:process-command world player "help")
      (is (not (null player))))))

(test command-processing-exits
  "Test the exits command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-add-character! world player)
      (apeiron.core:process-command world player "exits")
      (is (not (null player))))))

(test command-processing-inventory
  "Test the inventory command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-add-character! world player)
      (apeiron.core:process-command world player "inventory")
      (is (not (null player))))))

(test command-processing-go
  "Test the go command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-add-character! world player)
      (let ((start-room (apeiron.core:object-location player)))
        ;; Try to go north (should work from starting room)
        (apeiron.core:process-command world player "go north")
        ;; Player should have moved or stayed in same room
        (is (not (null (apeiron.core:object-location player))))))))

(test command-processing-unknown
  "Test unknown command handling"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
      (apeiron.core:world-add-character! world player)
      ;; Unknown command should not crash
      (apeiron.core:process-command world player "blahblah")
      (is (not (null player))))))

(test command-processing-eval
  "Test the eval command"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil)))
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
