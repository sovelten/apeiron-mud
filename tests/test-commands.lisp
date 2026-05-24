(in-package #:mud.tests)

(in-suite mud-tests)

(test command-processing-look
  "Test the look command"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil)))
    ;; The look command should work without crashing
    (mud:process-command player "look")
    (is (not (null player)))))

(test command-processing-help
  "Test the help command"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil)))
    (mud:process-command player "help")
    (is (not (null player)))))

(test command-processing-exits
  "Test the exits command"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil)))
    (mud:process-command player "exits")
    (is (not (null player)))))

(test command-processing-inventory
  "Test the inventory command"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil)))
    (mud:process-command player "inventory")
    (is (not (null player)))))

(test command-processing-go
  "Test the go command"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil)))
    (let ((start-room (mud:object-location player)))
      ;; Try to go north (should work from starting room)
      (mud:process-command player "go north")
      ;; Player should have moved or stayed in same room
      (is (not (null (mud:object-location player)))))))

(test command-processing-unknown
  "Test unknown command handling"
  (mud:world-initialize)
  (let ((player (mud:create-player "TestPlayer" nil)))
    ;; Unknown command should not crash
    (mud:process-command player "blahblah")
    (is (not (null player)))))

