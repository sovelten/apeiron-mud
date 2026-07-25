(in-package #:apeiron-test)

(in-suite core-suite)

;; ─── Account creation ───────────────────────────────────────────────────────

(test account-creation
  "Test that we can create an account with the expected fields"
  (let ((account (make-instance 'mud-account
                                :name "TestPlayer"
                                :password-hash "dummy-hash"
                                :email "test@example.com")))
    (is (equal "TestPlayer" (account-name account)))
    (is (equal "dummy-hash" (account-password-hash account)))
    (is (equal "test@example.com" (account-email account)))))
    ;; No account-character slot — only character has owner reference

;; ─── Password hashing ───────────────────────────────────────────────────────

(test password-hash-round-trip
  "Test that hashing a password and checking it works"
  (let* ((password "s3cr3t!")
         (hash (hash-password password)))
    (is (stringp hash)
        "Password hash should be a string")
    (is (find #\: hash)
        "Password hash should contain a colon separating salt and key")
    (is (check-password password hash)
        "Correct password should verify against stored hash")
    (is (not (check-password "wrong-password" hash))
        "Wrong password should not verify")
    (is (not (check-password "" hash))
        "Empty password should not verify")))

(test password-hash-unique-salt
  "Test that hashing the same password twice produces different hashes"
  (let ((hash1 (hash-password "same-password"))
        (hash2 (hash-password "same-password")))
    (is (not (string= hash1 hash2))
        "Same password hashed twice should produce different hashes
         due to random salt, preventing rainbow table attacks")))

(test check-password-invalid-hash
  "Test that check-password handles malformed hash strings gracefully"
  (is (not (check-password "anything" "not-a-valid-hash"))
      "Malformed hash (no colon) should not verify")
  (is (not (check-password "anything" ""))
      "Empty hash should not verify"))

;; ─── Account registration ──────────────────────────────────────────────────

(test register-account-success
  "Test successful account registration"
  (let* ((old-count (hash-table-count *accounts*))
         (account (register-account "NewPlayer" "password123"
                                    :email "new@example.com")))
    (is (not (null account))
        "Register should return an account")
    (is (equal "NewPlayer" (account-name account)))
    (is (equal "new@example.com" (account-email account)))
    (is (account-exists-p "NewPlayer")
        "Account should exist after registration")
    (is (= (1+ old-count) (hash-table-count *accounts*))
        "Account count should increase by one")))

(test register-account-duplicate
  "Test that registering the same name twice signals an error"
  (register-account "UniquePlayer" "pw")
  (signals error
    (register-account "UniquePlayer" "different-pw"))
  (signals error
    (register-account "  UniquePlayer  " "pw")
    "Whitespace-padded duplicate should also be rejected"))

(test register-account-empty-name
  "Test that empty account names are rejected"
  (signals error
    (register-account "" "password"))
  (signals error
    (register-account "   " "password")
    "Whitespace-only name should be rejected"))

(test register-account-empty-password
  "Test that empty passwords are rejected"
  (signals error
    (register-account "Player" "")))

;; ─── Account authentication ─────────────────────────────────────────────────

(test authenticate-account-success
  "Test successful authentication"
  (let* ((name "AuthPlayer")
         (password "correct-horse-battery-staple")
         (account (register-account name password)))
    (let ((result (authenticate-account name password)))
      (is (not (null result))
          "Authentication should succeed with correct password")
      (is (eq account result)
          "Authentication should return the same account object"))))

(test authenticate-account-wrong-password
  "Test that authentication fails with wrong password"
  (register-account "AuthPlayer2" "right-password")
  (is (null (authenticate-account "AuthPlayer2" "wrong-password"))
      "Authentication should fail with wrong password"))

(test authenticate-account-nonexistent
  "Test that authentication fails for non-existent accounts"
  (is (null (authenticate-account "NoSuchPlayer" "any-password"))
      "Authentication should fail for non-existent account"))

(test authenticate-account-case-insensitive
  "Test that account lookups are case-insensitive"
  (register-account "CasePlayer" "password")
  (is (not (null (authenticate-account "caseplayer" "password")))
      "Lowercase should work")
  (is (not (null (authenticate-account "CASEPLAYER" "password")))
      "Uppercase should work")
  (is (not (null (authenticate-account "CasePlayer" "password")))
      "Original case should work"))

;; ─── Account existence check ────────────────────────────────────────────────

(test account-exists-p
  "Test account-exists-p function"
  (is (not (account-exists-p "NonExistent")))
  (register-account "ExistenceTest" "pw")
  (is (account-exists-p "ExistenceTest"))
  (is (account-exists-p "existencetest")
      "Case-insensitive check should work"))

;; ─── Find account ───────────────────────────────────────────────────────────

(test find-account
  "Test find-account function"
  (is (null (find-account "Nobody")))
  (let ((account (register-account "FindMe" "pw")))
    (is (eq account (find-account "FindMe")))
    (is (eq account (find-account "findme"))
        "Case-insensitive find should work")))

;; ─── Account persistence ────────────────────────────────────────────────────

(test save-and-load-accounts
  "Test that accounts survive a save/load round-trip"
  ;; Clear accounts for a clean test
  (clrhash *accounts*)
  ;; Register some accounts
  (register-account "Persist1" "pw1" :email "p1@test.com")
  (register-account "Persist2" "pw2")
  (let ((count (hash-table-count *accounts*))
        (original-hash (account-password-hash (find-account "Persist1"))))
    ;; Save explicitly (register-account already saves, but explicit is fine)
    (save-accounts)
    ;; Clear in-memory state
    (clrhash *accounts*)
    (is (= 0 (hash-table-count *accounts*))
        "Accounts should be cleared from memory")
    ;; Reload
    (load-accounts)
    (is (= count (hash-table-count *accounts*))
        "Account count should match after reload")
    (is (account-exists-p "Persist1")
        "Persist1 should exist after reload")
    (is (account-exists-p "Persist2")
        "Persist2 should exist after reload")
    (is (equal "p1@test.com" (account-email (find-account "Persist1")))
        "Email should survive round-trip")
    (is (equal original-hash (account-password-hash (find-account "Persist1")))
        "Password hash should survive round-trip")
    ;; Passwords should still verify
    (is (not (null (authenticate-account "Persist1" "pw1")))
        "Password should still verify after reload")
    (is (not (null (authenticate-account "Persist2" "pw2")))
        "Password should still verify after reload")))

;; ─── Character-account association ──────────────────────────────────────────

(test character-owner-association
  "Test that a character is properly linked to its owning account"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)))
         (account (register-account "CharOwner" "password"))
         (character (new-character "Hero" session :owner (account-name account))))
    (is (equal "CharOwner" (character-owner character))
        "Character owner should be the account name")
    (is (eq session (character-session character))
        "Character session should still be set")))

(test guest-character-no-owner
  "Test that guest characters have no owner"
  (let* ((session (make-instance 'stream-session
                                 :stream (make-string-output-stream)))
         (character (new-character "Guest42" session)))
    (is (null (character-owner character))
        "Guest character should have no owner")))

;; ─── Password masking ───────────────────────────────────────────────────────

(test stream-session-read-secret-masks-input
  "Test that mud-read-secret on a stream-session echoes * for each character
and returns the correct password."
  (let* ((input (make-string-input-stream "s3cr3t!
"))
         ;; Use a two-way-stream so we can capture echoed output
         (output (make-string-output-stream))
         (combined (make-two-way-stream input output))
         (session (make-instance 'stream-session :stream combined)))
    (multiple-value-bind (line status)
        (mud-read-secret session)
      (is (null status) "Status should be NIL on success")
      (is (equal "s3cr3t!" line) "Should read the password correctly")
      ;; Each typed character should echo a *, plus a newline at end
      (let ((echoed (get-output-stream-string output)))
        (is (equal "*******
" echoed)
            "Each password character should echo a single * followed by newline")))))

(test stream-session-read-secret-empty-password
  "Test that mud-read-secret handles an empty password (just newline)."
  (let* ((input (make-string-input-stream "
"))
         (output (make-string-output-stream))
         (combined (make-two-way-stream input output))
         (session (make-instance 'stream-session :stream combined)))
    (multiple-value-bind (line status)
        (mud-read-secret session)
      (is (null status) "Status should be NIL")
      (is (equal "" line) "Should return empty string")
      (let ((echoed (get-output-stream-string output)))
        (is (equal "
" echoed) "Should echo only the newline, no asterisks")))))

(test stream-session-read-secret-eof
  "Test that mud-read-secret returns :eof when stream is exhausted."
  (let* ((input (make-string-input-stream ""))
         (output (make-string-output-stream))
         (combined (make-two-way-stream input output))
         (session (make-instance 'stream-session :stream combined)))
    (multiple-value-bind (line status)
        (mud-read-secret session)
      (is (null line) "Line should be NIL on EOF")
      (is (eq status :eof) "Status should be :eof"))))

(test ask-input-secret-delegates-to-mud-read-secret
  "Test that ask-input with :secret t calls mud-read-secret instead of
mud-read-line."
  (let* ((input (make-string-input-stream "mypass
"))
         (output (make-string-output-stream))
         (combined (make-two-way-stream input output))
         (session (make-instance 'stream-session :stream combined)))
    (let ((result (ask-input session "Password:" :secret t)))
      (is (equal "mypass" result) "Should return the password")
      (let ((output-str (get-output-stream-string output)))
        ;; The question "Password:" should be written, then newline,
        ;; then * for each char, then newline
        (is (search "Password:" output-str)
            "Should include the question prompt")
        (is (search "******" output-str)
            "Should include asterisks for each password character")))))

(test ask-input-secret-with-default
  "Test that ask-input with :secret t and empty input returns the default."
  (let* ((input (make-string-input-stream "
"))
         (output (make-string-output-stream))
         (combined (make-two-way-stream input output))
         (session (make-instance 'stream-session :stream combined)))
    (let ((result (ask-input session "Password:" :default "guest" :secret t)))
      (is (equal "guest" result) "Should return the default on empty input"))))
