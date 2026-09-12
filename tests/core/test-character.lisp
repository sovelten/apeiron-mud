(in-package #:apeiron-test)

(in-suite core-suite)

(test player-creation
  "Test that we can create a player"
  (apeiron.persistence:world-restore-or-initialize)
  (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
    (is (equal (apeiron.core:object-name player) "TestPlayer"))
    (is (typep player 'apeiron.core:mud-character))
    (is (listp (apeiron.core:container-contents player)))))

(test player-inventory
  "Test player inventory management"
  (apeiron.persistence:world-restore-or-initialize)
  (let ((player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream))))
        (obj (apeiron.core:new-room :name "Test Item")))
    (apeiron.core:container-add-object player obj)
    (is (= 1 (length (apeiron.core:container-contents player))))
    (is (eq obj (apeiron.core:container-object-by-id player (apeiron.core:object-id obj))))
    (apeiron.core:container-remove-object player obj)
    (is (= 0 (length (apeiron.core:container-contents player))))))

(test player-location
  "Test that player has a location"
  (let ((world (apeiron.persistence:world-restore-or-initialize))
        (player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)))))
    (apeiron.core:world-add-object! world player)
    (apeiron.core:place-character! world player)
    (is (not (null (apeiron.core:object-location player))))
    (is (typep (apeiron.core:object-location player) 'apeiron.core:mud-room))))

;; ─── Stamina and levelling ─────────────────────────────────────────────────

(defun make-stat-test-character (&optional (name "Stat Tester"))
  "A transient character used by the stat tests."
  (apeiron.core:new-character
   name
   (make-instance 'apeiron.core:stream-session
                  :stream (make-string-output-stream))))

(test character-default-stats
  "Every character starts at the base level of each stat, with max HP
derived from stamina.  The defaults are stored lazily, not merely
reported."
  (let ((character (make-stat-test-character "Newbie")))
    (is (= 10 (apeiron.core:character-stamina character)))
    (is (= 10 (apeiron.core:character-intelligence character)))
    (is (= 100 (apeiron.core:character-max-hp character)))
    (is (= 10 (apeiron.core:object-get-property character "stamina")))
    (is (= 10 (apeiron.core:object-get-property character "intelligence")))))

(test stat-points-follow-fibonacci
  "The points needed to gain each stat level follow the Fibonacci
progression 10, 10, 20, 30, 50, 80, 130, ... for levels 10, 11, 12, ..."
  (is (= 10  (apeiron.core:stat-points-to-advance 10)))
  (is (= 10  (apeiron.core:stat-points-to-advance 11)))
  (is (= 20  (apeiron.core:stat-points-to-advance 12)))
  (is (= 30  (apeiron.core:stat-points-to-advance 13)))
  (is (= 50  (apeiron.core:stat-points-to-advance 14)))
  (is (= 80  (apeiron.core:stat-points-to-advance 15)))
  (is (= 130 (apeiron.core:stat-points-to-advance 16))))

(test walking-raises-stamina
  "Stamina points raise stamina one level at a time."
  (let ((character (make-stat-test-character "Walker")))
    ;; Nine points are not yet enough for the first level.
    (loop repeat 9 do (apeiron.core:character-gain-stat-points character :stamina 1))
    (is (= 10 (apeiron.core:character-stamina character)))
    (is (= 9 (apeiron.core:character-stamina-points character)))
    ;; The tenth point levels up and clears the banked points.
    (is (= 1 (apeiron.core:character-gain-stat-points character :stamina 1)))
    (is (= 11 (apeiron.core:character-stamina character)))
    (is (= 0 (apeiron.core:character-stamina-points character)))
    ;; The next level again takes ten points.
    (loop repeat 9 do (apeiron.core:character-gain-stat-points character :stamina 1))
    (is (= 11 (apeiron.core:character-stamina character)))
    (is (= 1 (apeiron.core:character-gain-stat-points character :stamina 1)))
    (is (= 12 (apeiron.core:character-stamina character)))))

(test stamina-level-up-grows-max-hp
  "Maximum HP is derived from stamina and grows when stamina levels up."
  (let ((character (make-stat-test-character "Tough")))
    (apeiron.core:character-ensure-combat-stats character)
    (is (= 100 (apeiron.core:character-max-hp character)))
    (is (= 100 (apeiron.core:character-hp character)))
    (apeiron.core:character-gain-stat-points character :stamina 10)
    (is (= 11 (apeiron.core:character-stamina character)))
    (is (= 110 (apeiron.core:character-max-hp character)))
    ;; The character is granted the gained hit points.
    (is (= 110 (apeiron.core:character-hp character)))))

(test stat-caps-at-max-level
  "Stats stop growing at the maximum level."
  (let ((character (make-stat-test-character "Maxed")))
    (setf (apeiron.core:character-stamina character)
          apeiron.core:+character-max-stat+)
    (is (= 0 (apeiron.core:character-gain-stat-points character :stamina 1000)))
    (is (= apeiron.core:+character-max-stat+
           (apeiron.core:character-stamina character)))))

(test stat-level-up-message-is-yellow
  "Every stat's level-up message is yellow and mentions no numbers."
  (dolist (stat '(:stamina :intelligence))
    ;; Plain text (colors off) contains no digits.
    (let ((*colorize* nil))
      (is (null (find-if #'digit-char-p
                         (apeiron.core:character-stat-level-up-message stat)))))
    ;; With colors on it is wrapped in ANSI yellow (SGR 33) and reset.
    (let* ((*colorize* t)
           (message (apeiron.core:character-stat-level-up-message stat)))
      (is (stringp message))
      (is (search (format nil "~C[33m" (code-char 27)) message))
      (is (search (format nil "~C[0m" (code-char 27)) message)))))

(test solving-wordle-awards-intelligence
  "Solving a Wordle puzzle awards ten reasoning points, levelling
intelligence on the same Fibonacci scale."
  (let* ((room (apeiron.core:new-room :name "Puzzle Room"))
         (character (make-stat-test-character "Solver")))
    ;; handle-tell broadcasts the result to the room, so give it one.
    (apeiron.core:container-add-object room character)
    (is (= 10 (apeiron.core:character-intelligence character)))
    (let ((puzzle (apeiron.core:new-wordle-puzzle :target-word "apple")))
      (apeiron.core:handle-tell puzzle character "apple"))
    (is (= 11 (apeiron.core:character-intelligence character)))
    (is (= 0 (apeiron.core:character-intelligence-points character)))
    ;; A second correct solve on another puzzle levels it again.
    (let ((puzzle (apeiron.core:new-wordle-puzzle :target-word "brave")))
      (apeiron.core:handle-tell puzzle character "brave"))
    (is (= 12 (apeiron.core:character-intelligence character)))))

(test walking-via-go-command-raises-stamina
  "Each successful `go` awards a stamina point; ten of them raise stamina
to the next level and announce the progress in yellow."
  (let* ((world (apeiron.core:new-world))
         (north (apeiron.core:new-room :name "North"))
         (south (apeiron.core:new-room :name "South")))
    (apeiron.core:world-add-object! world north)
    (apeiron.core:world-add-object! world south)
    (apeiron.core:connect-north-south! world north south)
    (apeiron.core:world-set-starting-room! world north)
    (let ((character (apeiron.core:new-character
                      "Pacer"
                      (make-instance 'apeiron.core:stream-session
                                     :stream (make-string-output-stream)
                                     :use-colors t))))
      (apeiron.core:create-object! world character)
      (apeiron.core:place-character! world character)
      (let ((output (apeiron.core:session-stream
                     (apeiron.core:character-session character))))
        ;; Walk back and forth ten times → ten stamina points.
        (dotimes (i 10)
          (apeiron.core:process-command
           world character
           (if (evenp i) "go south" "go north")))
        (is (= 11 (apeiron.core:character-stamina character)))
        ;; The yellow level-up message was delivered.
        (is (search "Something deep within you"
                    (get-output-stream-string output)))))))
