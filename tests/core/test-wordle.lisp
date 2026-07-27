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
        (wordle-guess puzzle "TestCharacter" "train")
      (declare (ignore display))
      (is (eq :continue result-code)))))

(test wordle-guess-solved
  "Correct guess returns :solved"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "crane")
      (declare (ignore display))
      (is (eq :solved result-code)))))

(test wordle-guess-failed
  "Running out of guesses returns :failed"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 2)))
    (wordle-guess puzzle "TestCharacter" "train")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "dumpy")
      (declare (ignore display))
      (is (eq :failed result-code)))))

(test wordle-guess-already-solved
  "Guessing after already solved returns :already"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "TestCharacter" "crane")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "crane")
      (declare (ignore display))
      (is (eq :already result-code)))))

(test wordle-guess-already-failed
  "Guessing after already failed returns :already"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 1)))
    (wordle-guess puzzle "TestCharacter" "dumpy")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "train")
      (declare (ignore display))
      (is (eq :already result-code)))))

(test wordle-guess-invalid-length
  "Wrong length returns :invalid"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "cr")
      (declare (ignore display))
      (is (eq :invalid result-code)))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "cranes")
      (declare (ignore display))
      (is (eq :invalid result-code)))))

(test wordle-guess-invalid-characters
  "Non-alpha characters return :invalid"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "cran3")
      (declare (ignore display))
      (is (eq :invalid result-code)))))

(test wordle-guess-repeat
  "Repeating a previous guess returns :repeat"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "TestCharacter" "train")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "train")
      (declare (ignore display))
      (is (eq :repeat result-code)))))

(test wordle-guess-trims-whitespace
  "Guess is trimmed of whitespace"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "  crane  ")
      (declare (ignore display))
      (is (eq :solved result-code)))))

(test wordle-guess-case-insensitive
  "Guess is case-insensitive"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "CRANE")
      (declare (ignore display))
      (is (eq :solved result-code)))))

;; ─── Per-character state

(test wordle-per-character-independent
  "Two characters' guesses are tracked independently"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "Alice" "train")
    (wordle-guess puzzle "Bob" "crane")
    (is-false (wordle-character-solved-p puzzle "Alice"))
    (is-true (wordle-character-solved-p puzzle "Bob"))
    (is (= 1 (length (wordle-character-guesses-list puzzle "Alice"))))
    (is (= 1 (length (wordle-character-guesses-list puzzle "Bob"))))))

(test wordle-per-character-different-outcomes
  "One character can solve while another fails"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 2)))
    (wordle-guess puzzle "Bob" "dumpy")
    (wordle-guess puzzle "Bob" "train")
    (wordle-guess puzzle "Alice" "crane")
    (is-true (wordle-character-failed-p puzzle "Bob"))
    (is-true (wordle-character-solved-p puzzle "Alice"))))

;; ─── Display

(test wordle-display-header
  "Display includes puzzle name and description"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (let ((display (wordle-display puzzle "TestCharacter")))
      (is (search "a test wordle board" display))
      (is (search "A test board for wordle." display)))))

(test wordle-display-remaining-slots
  "Display shows empty slots for remaining guesses"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 3)))
    (wordle-guess puzzle "TestCharacter" "train")
    (let ((display (wordle-display puzzle "TestCharacter")))
      (is (search "Speak a 5-letter word" display))
      (is (search "2 guesses remaining" display)))))

(test wordle-display-solved-message
  "Display shows solved message with shareable result"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "TestCharacter" "crane")
    (let ((display (wordle-display puzzle "TestCharacter")))
      (is (search "I solved it" display))
      ;; Should NOT reveal the word
      (is (not (search "CRANE" display)))
      ;; Should show green emoji squares (all correct = all 5 solved)
      (is (search "🟩 🟩 🟩 🟩 🟩" display)))))

(test wordle-display-failed-message
  "Display shows failure message with shareable result"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 1)))
    (wordle-guess puzzle "TestCharacter" "dumpy")
    (let ((display (wordle-display puzzle "TestCharacter")))
      (is (search "Out of guesses" display))
      ;; Should NOT reveal the word
      (is (not (search "CRANE" display))))))

;; ─── Reset

(test wordle-reset-all
  "Reset clears all characters and optionally sets a new word"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "Alice" "crane")
    (wordle-guess puzzle "Bob" "train")
    (wordle-reset puzzle :new-word "quest")
    (is-false (wordle-character-solved-p puzzle "Alice"))
    (is-false (wordle-character-solved-p puzzle "Bob"))
    (is (equal "quest" (wordle-target-word puzzle)))))

(test wordle-reset-character
  "Reset-character clears a single character's state"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "Alice" "crane")
    (wordle-guess puzzle "Bob" "train")
    (wordle-reset-character puzzle "Alice")
    (is-false (wordle-character-solved-p puzzle "Alice"))
    (is-true (wordle-character-guesses-list puzzle "Bob"))
    (is (equal "crane" (wordle-target-word puzzle)))))

;; ─── Handle-tell

(test wordle-handle-tell-five-letter-word
  "handle-tell processes a 5-letter word as a guess"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         (room (new-room :name "test"))
         captured-messages)
    (setf (object-location character) room)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-tell puzzle character "crane"))
               (is (search "I solved it" (car captured-messages))))
          (setf (fdefinition 'character-send-message) old))))))

(test wordle-handle-tell-non-word-ignored
  "handle-tell returns nil for non-5-letter messages"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane")))
    (is-false (handle-tell puzzle character "hello there"))
    (is-false (handle-tell puzzle character "hi"))
    (is-false (handle-tell puzzle character "a b c d e"))
    (is-false (handle-tell puzzle character ""))))

(test wordle-handle-tell-non-alpha-ignored
  "handle-tell returns nil for non-alpha 5-char strings"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane")))
    (is-false (handle-tell puzzle character "12345"))
    (is-false (handle-tell puzzle character "cr@ne"))
    (is-false (handle-tell puzzle character "cra?e"))))

;; ─── Edge cases

(test wordle-empty-guess
  "Empty guess string returns :invalid"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "")
      (declare (ignore display))
      (is (eq :invalid result-code)))))

(test wordle-character-data-auto-creates
  "Character data is auto-created on first access"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (is (null (wordle-character-guesses-list puzzle "NewCharacter")))
    (is (eq 0 (length (wordle-character-guesses-list puzzle "NewCharacter"))))
    (is-false (wordle-character-solved-p puzzle "NewCharacter"))
    (is-false (wordle-character-failed-p puzzle "NewCharacter"))))

(test wordle-solved-then-repeat-returns-already
  "After solving, any further guess returns :already (not :repeat)"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-guess puzzle "TestCharacter" "crane")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "train")
      (declare (ignore display))
      (is (eq :already result-code)))))

(test wordle-max-guesses-exact
  "Guessing exactly max-guesses times then failing works"
  (let ((puzzle (make-test-puzzle :target-word "crane" :max-guesses 3)))
    (wordle-guess puzzle "TestCharacter" "dumpy")
    (wordle-guess puzzle "TestCharacter" "train")
    (multiple-value-bind (display result-code)
        (wordle-guess puzzle "TestCharacter" "noble")
      (declare (ignore display))
      (is (eq :failed result-code)))))

(test wordle-print-object
  "Print-object shows puzzle name and ID (not the secret word)"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (let ((repr (with-output-to-string (s) (print-object puzzle s))))
      (is (search "a test wordle board" repr))
      (is (search "ID:" repr))
      ;; Must NOT reveal the secret word
      (is (not (search "CRANE" repr))))))

(test wordle-handle-tell-help
  "handle-tell responds to 'help' with instructions"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-tell puzzle character "help"))
               (is (search "How to play" (car captured-messages)))
               (is (search "Guess the 5-letter word" (car captured-messages))))
          (setf (fdefinition 'character-send-message) old))))))

(test wordle-handle-tell-show
  "handle-tell responds to 'show' with the puzzle state"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-tell puzzle character "show"))
               (is (search "a test wordle board" (car captured-messages)))
               (is (search "Speak a 5-letter word" (car captured-messages))))
          (setf (fdefinition 'character-send-message) old))))))

(test wordle-handle-tell-five-letter-not-command
  "A 5-letter word like 'board' or 'state' is treated as a guess, not a command"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-tell puzzle character "show"))
               (is (search "Speak a 5-letter word" (car captured-messages)))
               (setf captured-messages '())
               (is-true (handle-tell puzzle character "board"))
               (is (search "=== a test wordle board" (car captured-messages)))
               (is (search "b o a r d" (car captured-messages)))
               (setf captured-messages '())
               (is-true (handle-tell puzzle character "state"))
               (is (search "s t a t e" (car captured-messages))))
          (setf (fdefinition 'character-send-message) old))))))

(test wordle-daily-word-deterministic
  "Daily word is deterministic for the same date"
  (let* ((word-list (vector "apple" "berry" "crane" "dance" "eagle"))
         (time-1 (encode-universal-time 0 0 0 15 6 2026))
         (time-2 (encode-universal-time 12 30 0 15 6 2026)))
    (is (equal (wordle-daily-word word-list time-1)
               (wordle-daily-word word-list time-2)))
    (is (equal "berry" (wordle-daily-word word-list time-1)))))

(test wordle-daily-rotation
  "After solving, when a new day arrives, the character sees a fresh puzzle"
  (let* ((word-list (vector "apple" "berry" "crane" "dance" "eagle"))
         (day-1 (encode-universal-time 0 0 0 15 6 2026))
         (day-2 (encode-universal-time 0 0 0 16 6 2026))
         (puzzle (new-wordle-puzzle :word-list word-list
                                    :target-word (wordle-daily-word word-list day-1)))
         (session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session)))
    (setf (wordle-word-date puzzle) (wordle-date-key day-1))
    (setf (wordle-target-word puzzle) (wordle-daily-word word-list day-1))
    (let ((*wordle-override-time* day-1))
      (multiple-value-bind (display result-code)
          (wordle-guess puzzle "TestCharacter" (wordle-daily-word word-list day-1))
        (declare (ignore display))
        (is (eq :solved result-code))
        (is-true (wordle-character-solved-p puzzle "TestCharacter"))))
    (let ((*wordle-override-time* day-2))
      (wordle-display puzzle "TestCharacter")
      (is-false (wordle-character-solved-p puzzle "TestCharacter"))
      (is (equal (wordle-daily-word word-list day-2)
                 (wordle-target-word puzzle)))
      (multiple-value-bind (display result-code)
          (wordle-guess puzzle "TestCharacter" (wordle-daily-word word-list day-2))
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
    (is-false (wordle-character-solved-p puzzle "Alice"))
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

;; ─── Leaderboard

(test wordle-leaderboard-slot-initialized
  "Leaderboard slot starts as an empty list"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (is (equal '() (wordle-leaderboard puzzle)))
    (is (listp (wordle-leaderboard puzzle)))))

(test wordle-leaderboard-record-first-solved
  "Recording a solved game creates entry with 1 play, 1 correct"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (let ((entries (wordle-leaderboard puzzle)))
      (is (= 1 (length entries)))
      (destructuring-bind (name plays correct) (first entries)
        (is (string= "alice" name))
        (is (= 1 plays))
        (is (= 1 correct))))))

(test wordle-leaderboard-record-first-failed
  "Recording a failed game creates entry with 1 play, 0 correct"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Bob" :failed)
    (let ((entries (wordle-leaderboard puzzle)))
      (is (= 1 (length entries)))
      (destructuring-bind (name plays correct) (first entries)
        (is (string= "bob" name))
        (is (= 1 plays))
        (is (= 0 correct))))))

(test wordle-leaderboard-record-increment-plays-and-correct
  "Recording a second solved game increments both plays and correct"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (let ((entries (wordle-leaderboard puzzle)))
      (is (= 1 (length entries)))
      (destructuring-bind (name plays correct) (first entries)
        (is (= 2 plays))
        (is (= 2 correct))))))

(test wordle-leaderboard-record-increment-plays-only
  "Recording a second failed game increments only plays, not correct"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (wordle-leaderboard-record! puzzle "Alice" :failed)
    (let ((entries (wordle-leaderboard puzzle)))
      (is (= 1 (length entries)))
      (destructuring-bind (name plays correct) (first entries)
        (is (= 2 plays))
        (is (= 1 correct))))))

(test wordle-leaderboard-record-multiple-accounts
  "Multiple accounts are tracked independently"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (wordle-leaderboard-record! puzzle "Bob" :solved)
    (wordle-leaderboard-record! puzzle "Charlie" :failed)
    (let ((entries (wordle-leaderboard puzzle)))
      (is (= 3 (length entries)))
      (let ((alice (assoc "alice" entries :test #'string=))
            (bob (assoc "bob" entries :test #'string=))
            (charlie (assoc "charlie" entries :test #'string=)))
        (is-true alice)
        (is (= 1 (second alice)))
        (is (= 1 (third alice)))
        (is-true bob)
        (is (= 1 (second bob)))
        (is (= 1 (third bob)))
        (is-true charlie)
        (is (= 1 (second charlie)))
        (is (= 0 (third charlie)))))))

(test wordle-leaderboard-record-case-insensitive
  "Account names are handled case-insensitively"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (wordle-leaderboard-record! puzzle "alice" :failed)
    (let ((entries (wordle-leaderboard puzzle)))
      (is (= 1 (length entries)))
      (destructuring-bind (name plays correct) (first entries)
        (is (string= "alice" name))
        (is (= 2 plays))
        (is (= 1 correct))))))

(test wordle-leaderboard-record-trims-whitespace
  "Account names are trimmed of whitespace"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "  Alice  " :solved)
    (let ((entries (wordle-leaderboard puzzle)))
      (destructuring-bind (name plays correct) (first entries)
        (is (string= "alice" name))
        (is (= 1 plays))
        (is (= 1 correct))))))

(test wordle-leaderboard-format-empty
  "Formatting an empty leaderboard shows appropriate message"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (let ((output (wordle-format-leaderboard puzzle)))
      (is (search "No Wordle leaderboard data" output)))))

(test wordle-leaderboard-format-header
  "Formatting a non-empty leaderboard includes header and columns"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (let ((output (wordle-format-leaderboard puzzle)))
      (is (search "Leaderboard" output))
      (is (search "Player" output))
      (is (search "Plays" output))
      (is (search "Correct" output))
      (is (search "Win%" output)))))

(test wordle-leaderboard-format-shows-player
  "Formatting shows the player name and stats"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (let ((output (wordle-format-leaderboard puzzle)))
      (is (search "alice" output))
      (is (search "1" output)))))

(test wordle-leaderboard-format-sorted-by-correct
  "Leaderboard is sorted by correct guesses descending"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Bob" :solved)      ; 1 correct
    (wordle-leaderboard-record! puzzle "Alice" :solved)     ; 1 correct, same
    (wordle-leaderboard-record! puzzle "Alice" :solved)     ; 2 correct now
    (let* ((entries (wordle-leaderboard puzzle))
           (sorted (sort (copy-list entries)
                         (lambda (a b)
                           (or (> (third a) (third b))
                               (and (= (third a) (third b))
                                    (> (second a) (second b))))))))
      (is (string= "alice" (first (first sorted))))
      (is (string= "bob" (first (second sorted)))))))

(test wordle-leaderboard-format-highlights-top
  "Top scorer is highlighted with bold green"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (wordle-leaderboard-record! puzzle "Bob" :failed)
    (let ((output (wordle-format-leaderboard puzzle)))
      ;; Alice (top scorer) should have bold green formatting
      (is (search "alice" output))
      (is (search "bob" output)))))

;; ─── Leaderboard via handle-tell

(test wordle-handle-tell-leaderboard-command
  "handle-tell responds to 'leaderboard' with leaderboard data"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-tell puzzle character "leaderboard"))
               (is (search "No Wordle leaderboard data" (car captured-messages))))
          (setf (fdefinition 'character-send-message) old))))))

(test wordle-handle-tell-stats-alias
  "handle-tell responds to 'stats' alias with leaderboard data"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-tell puzzle character "stats"))
               (is (search "No Wordle leaderboard data" (car captured-messages))))
          (setf (fdefinition 'character-send-message) old))))))

(test wordle-handle-tell-scores-alias
  "handle-tell responds to 'scores' alias with leaderboard data"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session))
         (puzzle (make-test-puzzle :target-word "crane"))
         captured-messages)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (is-true (handle-tell puzzle character "scores"))
               (is (search "No Wordle leaderboard data" (car captured-messages))))
          (setf (fdefinition 'character-send-message) old))))))

;; ─── Leaderboard stats recording during gameplay

(test wordle-handle-tell-solved-records-stat
  "Solving a puzzle records a stat for a registered (owner) character"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session :owner "TestAccount"))
         (puzzle (make-test-puzzle :target-word "crane"))
         (room (new-room :name "test"))
         captured-messages)
    (setf (object-location character) room)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (handle-tell puzzle character "crane")
               (let ((entries (wordle-leaderboard puzzle)))
                 (is (= 1 (length entries)))
                 (destructuring-bind (name plays correct) (first entries)
                   (is (string= "testaccount" name))
                   (is (= 1 plays))
                   (is (= 1 correct))))))
          (setf (fdefinition 'character-send-message) old)))))

(test wordle-handle-tell-failed-records-stat
  "Failing a puzzle records a stat for a registered (owner) character"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session :owner "TestAccount"))
         (puzzle (make-test-puzzle :target-word "crane" :max-guesses 1))
         (room (new-room :name "test"))
         captured-messages)
    (setf (object-location character) room)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (handle-tell puzzle character "dumpy")
               (let ((entries (wordle-leaderboard puzzle)))
                 (is (= 1 (length entries)))
                 (destructuring-bind (name plays correct) (first entries)
                   (is (string= "testaccount" name))
                   (is (= 1 plays))
                   (is (= 0 correct))))))
          (setf (fdefinition 'character-send-message) old)))))

(test wordle-handle-tell-guest-not-recorded
  "Guest characters (no owner) do NOT get recorded on the leaderboard"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "Guest" session :owner nil))
         (puzzle (make-test-puzzle :target-word "crane"))
         (room (new-room :name "test"))
         captured-messages)
    (setf (object-location character) room)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (handle-tell puzzle character "crane")
               (is (equal '() (wordle-leaderboard puzzle))))
          (setf (fdefinition 'character-send-message) old))))))

(test wordle-handle-tell-continue-not-recorded
  "A non-final guess does NOT record a leaderboard stat"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)
                                 :use-colors nil))
         (character (new-character "TestCharacter" session :owner "TestAccount"))
         (puzzle (make-test-puzzle :target-word "crane"))
         (room (new-room :name "test"))
         captured-messages)
    (setf (object-location character) room)
    (flet ((mock-send (p msg &key newline)
             (declare (ignore p newline))
             (push msg captured-messages)))
      (let ((old (fdefinition 'character-send-message)))
        (setf (fdefinition 'character-send-message) #'mock-send)
        (unwind-protect
             (progn
               (handle-tell puzzle character "train")
               (is (equal '() (wordle-leaderboard puzzle))))
          (setf (fdefinition 'character-send-message) old))))))

(test wordle-leaderboard-help-text
  "Help text mentions the leaderboard command"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (let ((help (wordle-help-text puzzle)))
      (is (search "leaderboard" help)))))

(test wordle-leaderboard-not-lost-on-reset
  "Resetting character guesses does NOT clear the leaderboard"
  (let ((puzzle (make-test-puzzle :target-word "crane")))
    (wordle-leaderboard-record! puzzle "Alice" :solved)
    (wordle-reset puzzle :new-word "quest")
    (is (= 1 (length (wordle-leaderboard puzzle))))))
