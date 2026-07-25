;;;; src/core/account.lisp — Player account management
;;;;
;;;; Provides account registration, authentication, and persistence
;;;; independent of the BKNR datastore.  Accounts are stored in a simple
;;;; .dat file under *DATA-DIRECTORY*.

(in-package #:apeiron.core)

;; ─── Account class ──────────────────────────────────────────────────────────

(defclass mud-account ()
  ((name :initarg :name
         :accessor account-name
         :documentation "Account login name (unique).")
   (password-hash :initarg :password-hash
                  :accessor account-password-hash
                  :documentation "Salted PBKDF2 hash of the password, stored as \"salt:hash\" hex strings.")
   (email :initarg :email
          :accessor account-email
          :initform nil
          :documentation "Email address for password recovery."))
  (:documentation "A player account for the MUD.

Accounts are independent of the BKNR persistence layer and are stored
in a plain .dat file under *DATA-DIRECTORY*.

Characters are NOT linked from the account — only the character carries
an OWNER reference (a string matching the account name)."))

(defmethod print-object ((account mud-account) stream)
  (print-unreadable-object (account stream :type t)
    (format stream "~A" (account-name account))))

;; ─── Account storage ────────────────────────────────────────────────────────

(defvar *accounts* (make-hash-table :test #'equal)
  "Hash table of all registered accounts, keyed by account name (string).")

(defun accounts-file-path ()
  "Return the pathname of the accounts data file."
  (merge-pathnames "accounts.dat" *data-directory*))

(defun %account-to-plist (account)
  "Serialize ACCOUNT to a property list suitable for file storage."
  (list :name (account-name account)
        :password-hash (account-password-hash account)
        :email (account-email account)))

(defun %plist-to-account (plist)
  "Deserialize a property list back into a MUD-ACCOUNT instance."
  (make-instance 'mud-account
                 :name (getf plist :name)
                 :password-hash (getf plist :password-hash)
                 :email (getf plist :email)))

(defun save-accounts ()
  "Write all accounts to the accounts data file.
Each account is serialized as a property list; the file contains one
list of all account plists."
  (ensure-directories-exist *data-directory*)
  (let ((account-plists
          (loop for account being the hash-values of *accounts*
                collect (%account-to-plist account))))
    (with-open-file (stream (accounts-file-path)
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      ;; Use PRINT for readability — the file is human-inspectable s-expressions.
      (prin1 account-plists stream)
      (terpri stream)))
  (log-message "Saved ~D account(s) to ~A"
               (hash-table-count *accounts*)
               (accounts-file-path)))

(defun load-accounts ()
  "Load accounts from the accounts data file into *ACCOUNTS*.
Existing in-memory accounts are preserved (not cleared) so that
reloading does not lose data that hasn't been saved yet."
  (let ((path (accounts-file-path)))
    (when (probe-file path)
      (handler-case
          (with-open-file (stream path :direction :input)
            (let ((plists (read stream nil nil)))
              (when plists
                (dolist (plist plists)
                  (let ((account (%plist-to-account plist)))
                    (setf (gethash (string-downcase (account-name account))
                                   *accounts*)
                          account))))))
        (error (e)
          (log-error "Failed to load accounts from ~A: ~A" path e)))
      (log-message "Loaded ~D account(s) from ~A"
                   (hash-table-count *accounts*) path))))

;; ─── Password hashing ───────────────────────────────────────────────────────

(defun hash-password (password)
  "Hash PASSWORD using PBKDF2 with a random 16-byte salt.
Returns a string of the form \"salt-hex:derived-key-hex\" suitable for
storage in MUD-ACCOUNT."
  (let* ((salt (ironclad:random-data 16))
         (kdf (ironclad:make-kdf 'ironclad:pbkdf2 :digest 'ironclad:sha256))
         (derived-key
           (ironclad:derive-key kdf
                                (ironclad:ascii-string-to-byte-array password)
                                salt
                                100000
                                32))
         (salt-hex (ironclad:byte-array-to-hex-string salt))
         (key-hex (ironclad:byte-array-to-hex-string derived-key)))
    (format nil "~A:~A" salt-hex key-hex)))

(defun check-password (password password-hash)
  "Verify PASSWORD against a stored PASSWORD-HASH (as produced by HASH-PASSWORD).
Returns T if the password matches, NIL otherwise."
  (let ((colon-pos (position #\: password-hash)))
    (unless colon-pos
      (return-from check-password nil))
    (let* ((salt-hex (subseq password-hash 0 colon-pos))
           (key-hex (subseq password-hash (1+ colon-pos)))
           (salt (ironclad:hex-string-to-byte-array salt-hex))
           (expected-key (ironclad:hex-string-to-byte-array key-hex))
           (kdf (ironclad:make-kdf 'ironclad:pbkdf2 :digest 'ironclad:sha256))
           (derived-key
             (ironclad:derive-key kdf
                                  (ironclad:ascii-string-to-byte-array password)
                                  salt
                                  100000
                                  32)))
      (ironclad:constant-time-equal derived-key expected-key))))

;; ─── Account management ─────────────────────────────────────────────────────

(defun account-exists-p (name)
  "Return T if an account with the given NAME (case-insensitive) exists."
  (let ((key (string-downcase (string-trim '(#\Space #\Tab) name))))
    (not (null (gethash key *accounts*)))))

(defun find-account (name)
  "Return the MUD-ACCOUNT with the given NAME, or NIL if not found.
Matching is case-insensitive."
  (let ((key (string-downcase (string-trim '(#\Space #\Tab) name))))
    (gethash key *accounts*)))

(defun register-account (name password &key email)
  "Register a new account with NAME and PASSWORD.
Signals an error if an account with the same name already exists.
EMAIL is optional and stored for password recovery.
Returns the newly created MUD-ACCOUNT."
  (let ((key (string-downcase (string-trim '(#\Space #\Tab) name)))
        (clean-name (string-trim '(#\Space #\Tab) name)))
    (when (zerop (length clean-name))
      (error "Account name cannot be empty."))
    (when (zerop (length password))
      (error "Password cannot be empty."))
    (when (gethash key *accounts*)
      (error "An account with the name ~S already exists." clean-name))
    (let ((account (make-instance 'mud-account
                                  :name clean-name
                                  :password-hash (hash-password password)
                                  :email (when email
                                           (string-trim '(#\Space #\Tab) email)))))
      (setf (gethash key *accounts*) account)
      (save-accounts)
      (log-message "Registered new account: ~A" clean-name)
      account)))

(defun authenticate-account (name password)
  "Authenticate an account by NAME and PASSWORD.
Returns the MUD-ACCOUNT on success, or NIL on failure."
  (let ((account (find-account name)))
    (when (and account
               (check-password password (account-password-hash account)))
      account)))

;; ─── Initialization ─────────────────────────────────────────────────────────

(load-accounts)

