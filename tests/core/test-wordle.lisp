;;;; tests/core/test-wordle.lisp — Tests for the Wordle puzzle game

(in-package #:apeiron-test)

(in-suite core-suite)

;; ─── Helpers

(defun make-test-puzzle (&key (target-word "crane") (max-guesses 6))
  "Create a wordle puzzle with a fixed target word for testing."
  (new-wordle-puzzle :name "a test wordle board"
                     :description "A test board for wordle."
                     :target-word target-word
                     :max-guesses max-guesses))

;; ─── Puzzle creation

(test wordle-creation-basic
  "Create a wordle puzzle with default parameters"
  (let ((puzzle (new-wordle-puzzle)))
    (is (typep puzzle 'mud-wordle-puzzle))
    (is (= 5 (length (wordle-target-word puzzle))))
    (is (= 6 (wordle-max-guesses puzzle)))
    (is (stringp (object-name puzzle)))
    (is (stringp (object-description puzzle)))))

(test wordle-creation-custom-target
  "Create a wordle puzzle with a specific target word"
  (let ((puzzle (make-test-puzzle :target-word "quest")))
    (is (equal "quest" (wordle-target-word puzzle)))))

(test wordle-creation-custom-max-guesses
  "Create a wordle puzzle with custom max guesses"
  (let ((puzzle (make-test-puzzle :max-guesses 4)))
    (is (= 4 (wordle-max-guesses puzzle)))))

(test wordle-creation-custom-name-description
  "Create a wordle puzzle with custom name and description"
  (let ((puzzle (new-wordle-puzzle :name "Riddle Sphinx"
                                   :description "A wise sphinx awaits your guess.")))
    (is (equal "Riddle Sphinx" (object-name puzzle)))
    (is (equal "A wise sphinx awaits your guess." (object-description puzzle)))))

(test wordle-creation-daily-word-length
  "Daily word is always 5 letters"
  (let ((puzzle (new-wordle-puzzle)))
    (is (= 5 (length (wordle-target-word puzzle))))))

;; ─── Word evaluation

(test wordle-evaluate-all-correct
  "All letters correct and in position"
  (is (equal '(:correct :correct :correct :correct :correct)
             (wordle-evaluate-guess "crane" "crane"))))

(test wordle-evaluate-all-absent
  "No letters match"
  (is (equal '(:absent :absent :absent :absent :absent)
             (wordle-evaluate-guess "crane" "dumpy"))))

(test wordle-evaluate-mixed
  "Mix of correct, present, and absent"
  (let ((result (wordle-evaluate-guess "crane" "train")))
    (is (eq :absent (nth 0 result)))
    (is (eq :correct (nth 1 result)))
    (is (eq :correct (nth 2 result)))
    (is (eq :absent (nth 3 result)))
    (is (eq :present (nth 4 result)))))

(test wordle-evaluate-case-insensitive
  "Evaluation is case-insensitive"
  (is (equal '(:correct :correct :correct :correct :correct)
             (wordle-evaluate-guess "CRANE" "crane")))
  (is (equal '(:correct :correct :correct :correct :correct)
             (wordle-evaluate-guess "crane" "CRANE"))))

(test wordle-evaluate-duplicate-letters
  "Duplicate letters in guess don't overcount when target has one"
  (let ((result (wordle-evaluate-guess "crane" "cocoa")))
    (is (eq :correct (nth 0 result)))
    (is (eq :absent  (nth 1 result)))
    (is (eq :absent  (nth 2 result)))
    (is (eq :absent  (nth 3 result)))
    (is (eq :present (nth 4 result)))))

(test wordle-evaluate-duplicate-in-target
  "Duplicate letters in target are handled correctly"
  (let ((result (wordle-evaluate-guess "abbey" "babel")))
    (is (eq :present (nth 0 result)))
    (is (eq :present (nth 1 result)))
    (is (eq :correct (nth 2 result)))
    (is (eq :correct (nth 3 result)))
    (is (eq :absent  (nth 4 result)))))

(test wordle-evaluate-triple-duplicate
  "Three same letters in guess, two in target"
  (let ((result (wordle-evaluate-guess "cacao" "canna")))
    (is (eq :correct (nth 0 result)))
    (is (eq :correct (nth 1 result)))
    (is (eq :absent  (nth 2 result)))
    (is (eq :absent  (nth 3 result)))
    (is (eq :present (nth 4 result)))))

;; ─── Guess processing

(test wordle-guess-valid-continue
  "A valid guess returns :continue when not solved"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "train")
      (declare (ignore display))
      (is (eq :continue result-code)))))

(test wordle-guess-solved
  "Correct guess returns :solved"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "crane")
      (declare (ignore display))
      (is (eq :solved result-code)))))

(test wordle-guess-failed
  "Running out of guesses returns :failed"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 2)))
    (wordle-guess puzzle "TestPlayer" "train")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "dumpy")
      (declare (ignore display))
      (is (eq :failed result-code)))))

(test wordle-guess-already-solved
  "Guessing after already solved returns :already"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "TestPlayer" "crane")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "crane")
      (declare (ignore display))
      (is (eq :already result-code)))))

(test wordle-guess-already-failed
  "Guessing after already failed returns :already"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 1)))
    (wordle-guess puzzle "TestPlayer" "dumpy")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "train")
      (declare (ignore display))
      (is (eq :already result-code)))))

(test wordle-guess-invalid-length
  "Wrong length returns :invalid"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "cr")
      (declare (ignore display))
      (is (eq :invalid result-code)))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "cranes")
      (declare (ignore display))
      (is (eq :invalid result-code)))))

(test wordle-guess-invalid-characters
  "Non-alpha characters return :invalid"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "cran3")
      (declare (ignore display))
      (is (eq :invalid result-code)))))

(test wordle-guess-repeat
  "Repeating a previous guess returns :repeat"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "TestPlayer" "train")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "train")
      (declare (ignore display))
      (is (eq :repeat result-code)))))

(test wordle-guess-trims-whitespace
  "Guess is trimmed of whitespace"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "  crane  ")
      (declare (ignore display))
      (is (eq :solved result-code)))))

(test wordle-guess-case-insensitive
  "Guess is case-insensitive"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "CRANE")
      (declare (ignore display))
      (is (eq :solved result-code)))))

;; ─── Per-player state

(test wordle-per-player-independent
  "Two players' guesses are tracked independently"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "Alice" "train")
    (wordle-guess puzzle "Bob" "crane")
    (is-false (wordle-player-solved-p puzzle "Alice"))
    (is-true (wordle-player-solved-p puzzle "Bob"))
    (is (= 1 (length (wordle-player-guesses-list puzzle "Alice"))))
    (is (= 1 (length (wordle-player-guesses-list puzzle "Bob"))))))

(test wordle-per-player-different-outcomes
  "One player can solve while another fails"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 2)))
    (wordle-guess puzzle "Bob" "dumpy")
    (wordle-guess puzzle "Bob" "train")
    (wordle-guess puzzle "Alice" "crane")
    (is-true (wordle-player-failed-p puzzle "Bob"))
    (is-true (wordle-player-solved-p puzzle "Alice"))))

;; ─── Display

(test wordle-display-header
  "Display includes puzzle name and description"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (let ((display (wordle-display puzzle "TestPlayer")))
      (is (search "a test wordle board" display))
      (is (search "A test board for wordle." display)))))

(test wordle-display-remaining-slots
  "Display shows empty slots for remaining guesses"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 3)))
    (wordle-guess puzzle "TestPlayer" "train")
    (let ((display (wordle-display puzzle "TestPlayer")))
      (is (search "Speak a 5-letter word" display))
      (is (search "2 guesses remaining" display)))))

(test wordle-display-solved-message
  "Display shows solved message"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "TestPlayer" "crane")
    (let ((display (wordle-display puzzle "TestPlayer")))
      (is (search "You solved it" display))
      (is (search "CRANE" display)))))

(test wordle-display-failed-message
  "Display shows failure message"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 1)))
    (wordle-guess puzzle "TestPlayer" "dumpy")
    (let ((display (wordle-display puzzle "TestPlayer")))
      (is (search "Out of guesses" display))
      (is (search "CRANE" display)))))

;; ─── Reset

(test wordle-reset-all
  "Reset clears all players and optionally sets a new word"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "Alice" "crane")
    (wordle-guess puzzle "Bob" "train")
    (wordle-reset puzzle :new-word "quest")
    (is-false (wordle-player-solved-p puzzle "Alice"))
    (is-false (wordle-player-solved-p puzzle "Bob"))
    (is (equal "quest" (wordle-target-word puzzle)))))

(test wordle-reset-player
  "Reset-player clears a single player's state"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "Alice" "crane")
    (wordle-guess puzzle "Bob" "train")
    (wordle-reset-player puzzle "Alice")
    (is-false (wordle-player-solved-p puzzle "Alice"))
    (is-true (wordle-player-guesses-list puzzle "Bob"))
    (is (equal "crane" (wordle-target-word puzzle)))))

;; ─── Handle-speech

(test wordle-handle-speech-five-letter-word
  "Handle-speech processes a 5-letter word as a guess"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (player (new-character "TestPlayer" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         (room (new-room :name "test"))
         captured-messages)
    (setf (object-location player) room)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'player-send-message)))
        (setf (fdefinition 'player-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-speech puzzle player "crane"))
               (is (search "You solved it" (car captured-messages))))
          (setf (fdefinition 'player-send-message) old))))))

(test wordle-handle-speech-non-word-ignored
  "Handle-speech returns nil for non-5-letter messages"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)))
         (player (new-character "TestPlayer" session))
         (puzzle (make-test-puzzle :target-word "crane")))
    (is-false (handle-speech puzzle player "hello there"))
    (is-false (handle-speech puzzle player "hi"))
    (is-false (handle-speech puzzle player "a b c d e"))
    (is-false (handle-speech puzzle player ""))))

(test wordle-handle-speech-non-alpha-ignored
  "Handle-speech returns nil for non-alpha 5-char strings"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)))
         (player (new-character "TestPlayer" session))
         (puzzle (make-test-puzzle :target-word "crane")))
    (is-false (handle-speech puzzle player "12345"))
    (is-false (handle-speech puzzle player "cr@ne"))
    (is-false (handle-speech puzzle player "cra?e"))))

;; ─── Edge cases

(test wordle-empty-guess
  "Empty guess string returns :invalid"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "")
      (declare (ignore display))
      (is (eq :invalid result-code)))))

(test wordle-player-data-auto-creates
  "Player data is auto-created on first access"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (is (null (wordle-player-guesses-list puzzle "NewPlayer")))
    (is (eq 0 (length (wordle-player-guesses-list puzzle "NewPlayer"))))
    (is-false (wordle-player-solved-p puzzle "NewPlayer"))
    (is-false (wordle-player-failed-p puzzle "NewPlayer"))))

(test wordle-solved-then-repeat-returns-already
  "After solving, any further guess returns :already (not :repeat)"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "TestPlayer" "crane")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "train")
      (declare (ignore display))
      (is (eq :already result-code)))))

(test wordle-max-guesses-exact
  "Guessing exactly max-guesses times then failing works"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 3)))
    (wordle-guess puzzle "TestPlayer" "dumpy")
    (wordle-guess puzzle "TestPlayer" "train")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestPlayer" "noble")
      (declare (ignore display))
      (is (eq :failed result-code)))))

(test wordle-print-object
  "Print-object shows puzzle name and word"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (let ((repr (with-output-to-string (s) (print-object puzzle s))))
      (is (search "a test wordle board" repr))
      (is (search "CRANE" repr)))))

(test wordle-handle-speech-help
  "Handle-speech responds to 'help' with instructions"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (player (new-character "TestPlayer" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'player-send-message)))
        (setf (fdefinition 'player-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-speech puzzle player "help"))
               (is (search "How to play" (car captured-messages)))
               (is (search "Guess the 5-letter word" (car captured-messages))))
          (setf (fdefinition 'player-send-message) old))))))

(test wordle-handle-speech-show
  "Handle-speech responds to 'show' with the puzzle state"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (player (new-character "TestPlayer" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'player-send-message)))
        (setf (fdefinition 'player-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-speech puzzle player "show"))
               (is (search "a test wordle board" (car captured-messages)))
               (is (search "Speak a 5-letter word" (car captured-messages))))
          (setf (fdefinition 'player-send-message) old))))))

(test wordle-handle-speech-five-letter-not-command
  "A 5-letter word like 'board' or 'state' is treated as a guess, not a command"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (player (new-character "TestPlayer" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'player-send-message)))
        (setf (fdefinition 'player-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-speech puzzle player "show"))
               (is (search "Speak a 5-letter word" (car captured-messages)))
               (setf captured-messages '())
               (is-true (handle-speech puzzle player "board"))
               (is (search "=== a test wordle board" (car captured-messages)))
               (is (search "b o a r d" (car captured-messages)))
               (setf captured-messages '())
               (is-true (handle-speech puzzle player "state"))
               (is (search "s t a t e" (car captured-messages))))
          (setf (fdefinition 'player-send-message) old))))))

(test wordle-daily-word-deterministic
  "Daily word is deterministic for the same date"
  (let* ((word-list (vector "apple" "berry" "crane" "dance" "eagle"))
         (time-1 (encode-universal-time 0 0 0 15 6 2026))
         (time-2 (encode-universal-time 12 30 0 15 6 2026)))
    (is (equal (wordle-daily-word word-list time-1)
               (wordle-daily-word word-list time-2)))
    (is (equal "berry" (wordle-daily-word word-list time-1)))))

(test wordle-daily-rotation
  "After solving, when a new day arrives, the player sees a fresh puzzle"
  (let* ((word-list (vector "apple" "berry" "crane" "dance" "eagle"))
         (day-1 (encode-universal-time 0 0 0 15 6 2026))
         (day-2 (encode-universal-time 0 0 0 16 6 2026))
         (puzzle (new-wordle-puzzle :word-list word-list
                                    :target-word (wordle-daily-word word-list day-1)))
         (session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (player (new-character "TestPlayer" session)))
    (setf (wordle-word-date puzzle) (wordle-date-key day-1))
    (setf (wordle-target-word puzzle) (wordle-daily-word word-list day-1))
    (let ((*wordle-override-time* day-1))
      (multiple-value-bind (display result-code)
          (wordle-guess puzzle "TestPlayer" (wordle-daily-word word-list day-1))
        (declare (ignore display))
        (is (eq :solved result-code))
        (is-true (wordle-player-solved-p puzzle "TestPlayer"))))
    (let ((*wordle-override-time* day-2))
      (wordle-display puzzle "TestPlayer")
      (is-false (wordle-player-solved-p puzzle "TestPlayer"))
      (is (equal (wordle-daily-word word-list day-2)
                 (wordle-target-word puzzle)))
      (multiple-value-bind (display result-code)
          (wordle-guess puzzle "TestPlayer" (wordle-daily-word word-list day-2))
        (declare (ignore display))
        (is (eq :solved result-code))))))

(test wordle-daily-word-changes-daily
  "Daily word changes when the date changes"
  (let* ((word-list (vector "apple" "berry" "crane" "dance" "eagle"))
         (day-1 (encode-universal-time 0 0 0 15 6 2026))
         (day-2 (encode-universal-time 0 0 0 16 6 2026)))
    (is (not (equal (wordle-daily-word word-list day-1)
                    (wordle-daily-word word-list day-2))))))

(test wordle-set-daily-word!
  "Set-daily-word! updates the puzzle to today's word and resets progress"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "Alice" "crane")
    (wordle-set-daily-word! puzzle)
    (is-false (wordle-player-solved-p puzzle "Alice"))
    (is (not (equal "crane" (wordle-target-word puzzle))))))

(test wordle-creation-uses-daily-word
  "Creating a puzzle without target-word uses the daily word"
  (let ((puzzle (new-wordle-puzzle
                 :word-list (vector "apple" "berry" "crane" "dance" "eagle"))))
    (is (= 5 (length (wordle-target-word puzzle))))
    (is (find (wordle-target-word puzzle)
              #("apple" "berry" "crane" "dance" "eagle")
              :test #'string=))))

(test wordle-help-text-format
  "Help text explains the rules and colour coding"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (let ((help (wordle-help-text puzzle)))
      (is (search "How to play" help))
      (is (search "5-letter word" help))
      (is (search "tell <puzzle>" help))
      (is (search "Colour guide" help)))))

(test wordle-object-describe-color
  "Object-describe identifies wordle puzzles"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (let ((desc (object-describe puzzle)))
      (is (search "a test wordle board" desc))
      (is (search (write-to-string (object-id puzzle)) desc)))))
