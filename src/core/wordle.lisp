;;;; src/core/wordle.lisp - Wordle puzzle game objects
;;;;
;;;; A Wordle-like puzzle that can be placed in a room for players to
;;;; interact with.  Each puzzle has a 5-letter target word and tracks
;;;; guesses per player independently.  Multiple players can play the
;;;; same puzzle simultaneously.

(in-package #:apeiron.core)

;; ─── Default word list ─────────────────────────────────────────────────────

(defparameter *wordle-default-words*
  (vector
   "about" "above" "abuse" "actor" "acute" "admit" "adopt" "adult" "after"
   "again" "agent" "agree" "ahead" "alarm" "album" "alert" "alien" "align"
   "alive" "allow" "alone" "along" "alter" "angel" "anger" "angle" "angry"
   "apart" "apple" "apply" "arena" "argue" "arise" "aside" "asset" "avoid"
   "award" "aware" "awful" "bacon" "badge" "basic" "basis" "batch" "beach"
   "beard" "beast" "begin" "being" "below" "bench" "berry" "birth" "black"
   "blade" "blame" "blank" "blast" "bleed" "blend" "bless" "blind" "block"
   "blood" "board" "boast" "bonus" "booth" "bound" "brain" "brand" "brave"
   "bread" "break" "breed" "brief" "bring" "broad" "broke" "brook" "brown"
   "brush" "buddy" "build" "built" "bunch" "burst" "cabin" "candy" "cargo"
   "carry" "catch" "cause" "cedar" "chain" "chair" "chaos" "charm" "chart"
   "chase" "cheap" "check" "cheek" "chess" "chest" "chief" "child" "chill"
   "choir" "civil" "claim" "clash" "class" "clean" "clear" "clerk" "climb"
   "cling" "clock" "close" "cloth" "cloud" "coach" "coast" "coral" "count"
   "court" "cover" "crack" "craft" "crane" "crash" "crawl" "crazy" "cream"
   "crest" "crime" "crisp" "cross" "crowd" "crown" "crush" "cubic" "curve"
   "cycle" "daily" "dance" "debut" "decor" "depth" "derby" "desk" "dirty"
   "doubt" "dozen" "draft" "drain" "drama" "drank" "drawo" "dream" "dress"
   "dried" "drift" "drill" "drink" "drive" "drown" "drums" "dying" "eager"
   "eagle" "early" "earth" "eight" "elbow" "elder" "elect" "elite" "empty"
   "enemy" "enjoy" "enter" "entry" "equal" "equip" "error" "essay" "event"
   "every" "evict" "exact" "exile" "exist" "extra" "fable" "facet" "faith"
   "fancy" "fatal" "fault" "feast" "fence" "ferry" "fetch" "fever" "fiber"
   "field" "fierce" "fight" "final" "finch" "firm" "fixed" "flame" "flash"
   "fleet" "flesh" "float" "flock" "flood" "floor" "flora" "flour" "fluid"
   "flush" "flute" "focal" "focus" "force" "forge" "forth" "forum" "found"
   "frame" "frank" "fraud" "fresh" "front" "frost" "froze" "fruit" "fully"
   "gauge" "ghost" "giant" "given" "glass" "glide" "globe" "gloom" "glory"
   "gloss" "glove" "going" "grace" "grade" "grain" "grand" "grant" "grape"
   "grasp" "grass" "grave" "great" "green" "greet" "grief" "grill" "grind"
   "groan" "groom" "gross" "group" "grove" "guard" "guess" "guest" "guide"
   "guild" "guilt" "gully" "happy" "harsh" "haste" "haunt" "haven" "heart"
   "heavy" "hedge" "hence" "herbs" "hobby" "honey" "honor" "horse" "hotel"
   "house" "hover" "human" "humor" "hurry" "ideal" "image" "imply" "index"
   "indie" "infer" "inner" "input" "irony" "ivory" "jewel" "joint" "joker"
   "judge" "juice" "jumbo" "jumpy" "kebab" "knack" "kneel" "knife" "knock"
   "known" "label" "labor" "lance" "large" "laser" "later" "laugh" "layer"
   "learn" "lease" "leave" "legal" "lemon" "level" "lever" "light" "limit"
   "linen" "liver" "local" "logic" "loose" "lover" "lower" "loyal" "lucky"
   "lunar" "lunch" "lyric" "major" "maker" "manor" "maple" "march" "marry"
   "marsh" "match" "maybe" "mayor" "meant" "media" "mercy" "merge" "merit"
   "merry" "metal" "midst" "might" "minor" "minus" "mixed" "model" "money"
   "month" "moral" "motor" "mount" "mouse" "mouth" "movie" "music" "naive"
   "nanny" "nasty" "naval" "nerve" "never" "night" "noble" "noise" "north"
   "noted" "novel" "nurse" "nylon" "oasis" "occur" "ocean" "offer" "often"
   "olive" "onset" "opera" "orbit" "order" "organ" "other" "outer" "overt"
   "owner" "ozone" "paint" "panel" "panic" "paper" "party" "pasta" "patch"
   "pause" "peace" "pearl" "penny" "phase" "phone" "photo" "piano" "piece"
   "pilot" "pinch" "pitch" "pixel" "place" "plain" "plane" "plant" "plate"
   "plaza" "pluck" "plumb" "plume" "plump" "point" "polar" "pound" "power"
   "press" "price" "pride" "prime" "prince" "print" "prior" "prism" "prize"
   "probe" "proof" "prose" "proud" "prove" "pulse" "punch" "pupil" "purse"
   "queen" "query" "quest" "queue" "quick" "quiet" "quite" "quota" "quote"
   "radar" "radio" "rally" "ranch" "range" "rapid" "ratio" "reach" "react"
   "ready" "realm" "rebel" "refer" "reign" "relax" "reply" "rider" "ridge"
   "rifle" "right" "rigid" "risky" "rival" "river" "robot" "rocky" "rouge"
   "rough" "round" "route" "royal" "rugby" "ruler" "rural" "sadly" "sauce"
   "scale" "scare" "scene" "scent" "scope" "score" "sense" "serve" "setup"
   "seven" "shade" "shaft" "shake" "shall" "shame" "shape" "share" "shark"
   "sharp" "shave" "sheer" "sheet" "shelf" "shell" "shift" "shine" "shirt"
   "shock" "shore" "short" "shout" "shove" "sight" "sigma" "since" "sixth"
   "sixty" "skate" "skill" "skull" "slash" "sleep" "slice" "slide" "small"
   "smart" "smell" "smile" "smoke" "snack" "snake" "solar" "solid" "solve"
   "sorry" "sound" "south" "space" "spare" "spark" "speak" "speed" "spell"
   "spend" "spice" "spill" "spine" "spite" "split" "spoke" "sport" "spray"
   "squad" "stack" "staff" "stage" "stain" "stair" "stake" "stale" "stall"
   "stamp" "stand" "stark" "start" "state" "stays" "steal" "steam" "steel"
   "steep" "steer" "stern" "stick" "stiff" "still" "stock" "stone" "stood"
   "store" "storm" "story" "stove" "strap" "straw" "strip" "stuck" "study"
   "stuff" "style" "sugar" "suite" "sunny" "super" "surge" "swamp" "swear"
   "sweep" "sweet" "swept" "swift" "swing" "sword" "swore" "sworn" "syrup"
   "table" "taste" "teach" "teeth" "thank" "theft" "their" "theme" "there"
   "these" "thick" "thief" "thing" "think" "third" "thorn" "those" "three"
   "threw" "throw" "thumb" "tiger" "tight" "timer" "tired" "title" "toast"
   "today" "token" "total" "touch" "tough" "tower" "toxic" "trace" "track"
   "trade" "trail" "train" "trait" "trash" "treat" "trend" "trial" "tribe"
   "trick" "tried" "trip" "troop" "truck" "truly" "trump" "trunk" "trust"
   "truth" "tumor" "twice" "twist" "ultra" "uncle" "under" "unfair" "union"
   "unite" "unity" "until" "upper" "upset" "urban" "usage" "usual" "valid"
   "value" "valve" "vault" "verse" "video" "vigor" "vinyl" "viral" "virus"
   "visit" "vista" "vital" "vivid" "vocal" "vodka" "voice" "voter" "vouch"
   "wagon" "waist" "waste" "watch" "water" "weave" "wedge" "weigh" "weird"
   "whale" "wheat" "wheel" "where" "which" "while" "whine" "white" "whole"
   "whose" "wider" "witch" "woman" "world" "worry" "worse" "worst" "worth"
   "would" "wound" "wrath" "write" "wrong" "wrote" "yacht" "yield" "young"
   "youth" "zebra")
  "Default vector of 5-letter words for Wordle puzzles.")

;; ─── Daily word selection ─────────────────────────────────────────────────

(defvar *wordle-override-time* nil
  "When non-NIL, overrides the time used by WORDLE-DATE-KEY and
  WORDLE-ENSURE-FRESH-WORD! for testing purposes.")

(defun wordle-now ()
  "Return the current universal time, or the override time for testing."
  (or *wordle-override-time* (get-universal-time)))

(defun wordle-daily-word (&optional (word-list *wordle-default-words*)
                            (universal-time (wordle-now)))
  "Return a deterministic word from WORD-LIST based on the date.
  Same date always gives the same word; word changes daily."
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time universal-time)
    (declare (ignore second minute hour))
    (let ((day-index (+ day (* month 31) (* year 365))))
      (aref word-list (mod day-index (length word-list))))))

(defun wordle-set-daily-word! (puzzle &optional (universal-time (get-universal-time)))
  "Set the puzzle's target word to today's daily word and reset all player progress."
  (wordle-reset puzzle :new-word (wordle-daily-word (wordle-word-list puzzle)
                                                     universal-time)))

(defun wordle-date-key (&optional (universal-time (wordle-now)))
  "Return an integer YYYYMMDD for UNIVERSAL-TIME, for date comparisons."
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time universal-time)
    (declare (ignore second minute hour))
    (+ (* year 10000) (* month 100) day)))

(defun wordle-ensure-fresh-word! (puzzle &optional (universal-time (wordle-now)))
  "If the puzzle's word is stale (different date than UNIVERSAL-TIME), rotate
  to today's daily word and clear all player state.  Returns T if rotated, NIL
  if the word was already current."
  (let ((today (wordle-date-key universal-time)))
    (unless (= today (wordle-word-date puzzle))
      (wordle-set-daily-word! puzzle universal-time)
      (setf (wordle-word-date puzzle) today)
      t)))

;; ─── Wordle puzzle class ───────────────────────────────────────────────────

(defclass mud-wordle-puzzle (mud-object)
  ((target-word :initarg :target-word
                :accessor wordle-target-word
                :initform "world"
                :documentation "The 5-letter word players must guess.")
   (player-guesses :initarg :player-guesses
                   :accessor wordle-player-guesses
                   :initform (make-hash-table :test #'equal)
                   :documentation
                   "Hash table mapping player-name => plist of guess data.
                    Each entry is a plist with:
                      :guesses  - list of guess words (strings)
                      :solved   - whether this player solved it
                      :failed   - whether this player ran out of guesses")
   (max-guesses :initarg :max-guesses
                :accessor wordle-max-guesses
                :initform 6
                :documentation "Maximum allowed guesses per player.")
   (word-list :initarg :word-list
              :accessor wordle-word-list
              :initform *wordle-default-words*
              :documentation "Vector of valid words for random selection.")
   (word-date :initarg :word-date
              :accessor wordle-word-date
              :initform (wordle-date-key)
              :documentation "Integer date key (YYYYMMDD) of the current target-word."))
  (:documentation "A Wordle-like puzzle object for the MUD.

Players interact with the puzzle by telling it words.  Each player's
guesses are tracked independently.  When a new day arrives the puzzle
automatically rotates to that day's word and resets all progress."))

(defmethod object-describe ((obj mud-wordle-puzzle))
  "Magenta for Wordle puzzles."
  (magenta (format nil "~A (ID: ~D)" (object-name obj) (object-id obj))))

;; ─── Constructor ────────────────────────────────────────────────────────────

(defun new-wordle-puzzle (&key
                           (name "a Wordle puzzle board")
                           (description
                            "A large wooden board with five-letter slots neatly
arranged.  Coloured pegs sit in trays beside it, ready to mark each guess.")
                           target-word
                           (max-guesses 6)
                           (word-list *wordle-default-words*))
  "Create a new Wordle puzzle object.

TARGET-WORD is the 5-letter word to guess.  If not provided, the daily
word (based on today's date) is used.  The daily word is the same for
all puzzles created on the same date."
  (make-instance 'mud-wordle-puzzle
                 :name name
                 :description description
                 :target-word (or target-word
                                   (wordle-daily-word word-list))
                 :max-guesses max-guesses
                 :word-list word-list))

;; ─── Per-player state management ───────────────────────────────────────────

(defun wordle-player-data (puzzle player-name)
  "Get the guess data plist for PLAYER-NAME, creating it if needed."
  (let ((data (gethash player-name (wordle-player-guesses puzzle))))
    (unless data
      (setf data (list :guesses '() :solved nil :failed nil))
      (setf (gethash player-name (wordle-player-guesses puzzle)) data))
    data))

(defun wordle-player-guesses-list (puzzle player-name)
  "Get the list of guesses for PLAYER-NAME."
  (getf (wordle-player-data puzzle player-name) :guesses))

(defun wordle-player-solved-p (puzzle player-name)
  "Check if PLAYER-NAME has solved the puzzle."
  (getf (wordle-player-data puzzle player-name) :solved))

(defun wordle-player-failed-p (puzzle player-name)
  "Check if PLAYER-NAME has failed the puzzle."
  (getf (wordle-player-data puzzle player-name) :failed))

;; ─── Core game logic ───────────────────────────────────────────────────────

(defun wordle-evaluate-guess (target-word guess-word)
  "Evaluate a guess against the target word.

Returns a list of 5 keyword results:
  :correct   - letter is correct and in the right position
  :present   - letter is in the word but wrong position
  :absent    - letter is not in the word at all

Handles duplicate letters correctly: if a letter appears twice in the
guess but only once in the target, only one gets :present and the other
gets :absent."
  (let* ((target (string-downcase target-word))
         (guess  (string-downcase guess-word))
         (target-chars (coerce target 'list))
         (guess-chars  (coerce guess 'list))
         (results (make-list 5 :initial-element nil))
         ;; Count remaining unaccounted-for letters in target
         (remaining (copy-list target-chars)))
    ;; First pass: find correct positions
    (loop for i from 0 below 5
          do (when (char= (nth i guess-chars) (nth i target-chars))
               (setf (nth i results) :correct
                     (nth i remaining) nil)))
    (setf remaining (remove nil remaining))
    ;; Second pass: find present letters
    (loop for i from 0 below 5
          for guess-char = (nth i guess-chars)
          when (null (nth i results))
            do (let ((pos (position guess-char remaining)))
                 (if pos
                     (progn
                       (setf (nth i results) :present
                             (nth pos remaining) nil))
                     (setf (nth i results) :absent))))
    results))

;; ─── Display helpers ───────────────────────────────────────────────────────

(defun wordle-format-letter (char result)
  "Format a single letter with ANSI colours based on the result.

  :correct - green background, white text
  :present - yellow background, white text
  :absent  - dim text (greyed out)"
  (let ((letter (string char)))
    (ecase result
      (:correct (color-text letter +sgr-bold+ +sgr-fg-white+ +sgr-bg-green+))
      (:present (color-text letter +sgr-bold+ +sgr-fg-black+ +sgr-bg-yellow+))
      (:absent  (color-text letter +sgr-dim+)))))

(defun wordle-format-guess-line (guess-word results)
  "Format a single guess line with coloured letters separated by spaces."
  (let ((chars (coerce (string-downcase guess-word) 'list)))
    (format nil "  ~{~A~^ ~}"
            (loop for i from 0 below 5
                  collect (wordle-format-letter (nth i chars) (nth i results))))))

(defun wordle-format-empty-line ()
  "Format an empty slot line."
  (format nil "  ~A" (color-text "· · · · ·" +sgr-dim+)))

;; ─── Display the puzzle ────────────────────────────────────────────────────

(defun wordle-display (puzzle player-name)
  "Display the Wordle puzzle state for PLAYER-NAME.

Shows the board with all guesses and the remaining empty slots."
  (wordle-ensure-fresh-word! puzzle)
  (let* ((guesses  (wordle-player-guesses-list puzzle player-name))
         (solved   (wordle-player-solved-p puzzle player-name))
         (failed   (wordle-player-failed-p puzzle player-name))
         (target   (wordle-target-word puzzle))
         (max      (wordle-max-guesses puzzle))
         (n-guesses (length guesses)))
    (with-output-to-string (stream)
      ;; Header
      (format stream "~A~%~A~%~%"
              (bold-white (format nil "=== ~A ===" (object-name puzzle)))
              (object-description puzzle))
      ;; Guesses
      (dolist (pair guesses)
        (let ((guess-word (car pair))
              (results   (cdr pair)))
          (write-string (wordle-format-guess-line guess-word results) stream)
          (terpri stream)))
      ;; Empty slots
      (loop for i from n-guesses below max
            do (write-string (wordle-format-empty-line) stream)
               (terpri stream))
      ;; Result message
      (terpri stream)
      (cond
        (solved
         (format stream "~A~%"
                 (bold-green (format nil "You solved it in ~D ~A! The word was: ~A"
                                     n-guesses
                                     (if (= n-guesses 1) "guess" "guesses")
                                     (string-upcase target)))))
        (failed
         (format stream "~A~%"
                 (bold-red (format nil "Out of guesses! The word was: ~A"
                                   (string-upcase target)))))
        (t
         (format stream "~A~%"
                 (yellow (let ((rem (- max n-guesses)))
                          (format nil "Speak a 5-letter word aloud (~D ~A remaining)"
                                  rem (if (= rem 1) "guess" "guesses"))))))))))

;; ─── Make a guess ──────────────────────────────────────────────────────────

(defun wordle-guess (puzzle player-name guess-word)
  "Process a guess from PLAYER-NAME.

Returns multiple values:
  (values display-string result-code)
where RESULT-CODE is one of:
  :solved   - correct guess
  :continue - valid guess, keep going
  :failed   - out of guesses
  :invalid  - invalid word (wrong length, not letters)
  :already  - already solved/failed this puzzle
  :repeat   - already guessed this word"
  ;; Rotate word if a new day has arrived
  (wordle-ensure-fresh-word! puzzle)
  ;; Check for already-complete
  (let ((solved (wordle-player-solved-p puzzle player-name))
        (failed (wordle-player-failed-p puzzle player-name)))
    (when solved
      (return-from wordle-guess
        (values (wordle-display puzzle player-name) :already)))
    (when failed
      (return-from wordle-guess
        (values (wordle-display puzzle player-name) :already))))
  ;; Validate guess
  (let* ((cleaned (string-trim '(#\Space #\Tab #\Newline) guess-word))
         (lower   (string-downcase cleaned)))
    (unless (= (length lower) 5)
      (return-from wordle-guess
        (values (format nil "~A Speak a 5-letter word."
                        (yellow "The board ignores:"))
                :invalid)))
    (unless (every (lambda (c) (find c "abcdefghijklmnopqrstuvwxyz"))
                   lower)
      (return-from wordle-guess
        (values (format nil "~A Speak only letters A-Z."
                        (yellow "The board ignores:"))
                :invalid)))
    ;; Check for repeated guess
    (let ((guesses (wordle-player-guesses-list puzzle player-name)))
      (when (find lower guesses :test (lambda (a b) (string= a b))
                  :key #'car)
        (return-from wordle-guess
          (values (format nil "~A You already guessed '~A'."
                          (yellow "Repeat:")
                          (string-upcase lower))
                  :repeat))))
    ;; Evaluate
    (let* ((target (wordle-target-word puzzle))
           (results (wordle-evaluate-guess target lower))
           (guesses (wordle-player-guesses-list puzzle player-name))
           (new-guesses (append guesses (list (cons lower results))))
           (data (wordle-player-data puzzle player-name)))
      ;; Record the guess
      (setf (getf data :guesses) new-guesses)
      ;; Check for win
      (if (every (lambda (r) (eq r :correct)) results)
          (progn
            (setf (getf data :solved) t)
            (values (wordle-display puzzle player-name) :solved))
          ;; Check for failure
          (if (>= (length new-guesses) (wordle-max-guesses puzzle))
              (progn
                (setf (getf data :failed) t)
                (values (wordle-display puzzle player-name) :failed))
              ;; Continue
              (values (wordle-display puzzle player-name) :continue))))))

;; ─── Reset ─────────────────────────────────────────────────────────────────

(defun wordle-reset (puzzle &key new-word)
  "Reset the puzzle for all players.  Optionally set a NEW-WORD.
  When NEW-WORD is given the WORD-DATE is updated to today."
  (clrhash (wordle-player-guesses puzzle))
  (when new-word
    (setf (wordle-target-word puzzle) new-word)
    (setf (wordle-word-date puzzle) (wordle-date-key)))
  t)

(defun wordle-reset-player (puzzle player-name)
  "Reset the puzzle for a single player."
  (remhash player-name (wordle-player-guesses puzzle))
  t)

;; ─── Help text ────────────────────────────────────────────────────────────

(defun wordle-help-text (puzzle)
  "Return a help string explaining how to play Wordle on this puzzle."
  (wordle-ensure-fresh-word! puzzle)
  (with-output-to-string (stream)
    (format stream "~A~%~%" (bold-white (format nil "=== How to play ~A ===" (object-name puzzle))))
    (format stream "~A~%~A~%~%" (bold-white "Goal:") "Guess the 5-letter word in 6 tries.")
    (format stream "~A~%~A~%~A~%~A~%~%" (bold-white "How to play:")
            "  tell <puzzle> <word>  - Make a guess (e.g. tell board crane)"
            "  tell <puzzle> help    - Show this help"
            "  tell <puzzle> show    - Show the current puzzle state")
    (format stream "~A~%~A~%~A~%~A~%~A"
            (bold-white "Colour guide:")
            (format nil "  ~A - Letter is correct and in the right position"
                    (color-text " G " +sgr-bold+ +sgr-fg-white+ +sgr-bg-green+))
            (format nil "  ~A - Letter is in the word but wrong position"
                    (color-text " Y " +sgr-bold+ +sgr-fg-black+ +sgr-bg-yellow+))
            (format nil "  ~A - Letter is not in the word at all"
                    (color-text " . " +sgr-dim+))
            "")))

;; ─── Speech interaction ────────────────────────────────────────────────────

(defmethod handle-speech ((puzzle mud-wordle-puzzle) speaker message)
  "Respond when a player tells the puzzle a 5-letter word, help, or board."
  (wordle-ensure-fresh-word! puzzle)
  (let* ((cleaned (string-trim '(#\Space #\Tab #\Newline) message))
         (lower (string-downcase cleaned)))
    (cond
      ;; "help" — show instructions
      ((member lower '("help" "instructions" "rules") :test #'string=)
       (player-send-message speaker (wordle-help-text puzzle))
       t)
      ;; "show" — show current puzzle state
      ((member lower '("show") :test #'string=)
       (player-send-message speaker (wordle-display puzzle (object-name speaker)))
       t)
      ;; 5-letter word — process as a guess
      ((and (= (length lower) 5)
            (every (lambda (c) (find c "abcdefghijklmnopqrstuvwxyz")) lower))
       (multiple-value-bind (display result-code)
           (wordle-guess puzzle (object-name speaker) lower)
         (player-send-message speaker display)
         (when (or (eq result-code :solved) (eq result-code :failed))
           (let ((room (object-location speaker)))
             (loop for obj in (container-all-objects room)
                   do (when (and (typep obj 'mud-character)
                                 (not (eq obj speaker)))
                        (player-send-message
                         obj
                         (format nil "~A ~A the Wordle puzzle!"
                                 (bright-green (object-name speaker))
                                 (if (eq result-code :solved)
                                     (bold-green "solved")
                                     (bold-red "failed to solve"))))))))
         (not (eq result-code :invalid))))
      ;; Anything else — not handled here
      (t nil))))

;; ─── Print-object ──────────────────────────────────────────────────────────

(defmethod print-object ((puzzle mud-wordle-puzzle) stream)
  (print-unreadable-object (puzzle stream :type t)
    (format stream "~A - word: ~A"
            (object-name puzzle)
            (string-upcase (wordle-target-word puzzle)))))
