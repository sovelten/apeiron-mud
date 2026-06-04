(in-package #:mud)

;; Player registration and authentication module
;; Handles player registration, login, and password management
;; All data is kept in memory during the running instance

(defvar *registered-players* (make-hash-table :test #'equal)
  "Hash table of registered players, keyed by username
   Values are plists with :password-hash, :display-name, :player-object, etc.")

(defvar *players-by-username* (make-hash-table :test #'equal)
  "Hash table mapping usernames to their player objects
   This allows us to track players across connections")

(defvar *password-salt* "mud-server-salt-2024"
  "Salt used for password hashing")

;; Simple password hashing using a deterministic hash
;; This is a simple implementation - in production you'd want bcrypt or similar
(defun hash-password (password)
  "Hash a password by combining it with a salt and using sxhash.
   Returns a hex string of the hash."
  (let* ((salted (concatenate 'string password *password-salt*))
         (hash-value (sxhash salted)))
    (format nil "~X" (abs hash-value))))

(defun verify-password (password hash)
  "Verify that a password matches its hash."
  (string= (hash-password password) hash))

(defun player-exists-p (username)
  "Check if a player with the given username already exists."
  (gethash username *registered-players*))

(defun get-player-object (username)
  "Get the player object for a registered player."
  (gethash username *players-by-username*))

(defun register-new-player (username password display-name player-obj)
  "Register a new player with username, password, display name, and player object.
   Returns T if successful, NIL if username already exists."
  (if (player-exists-p username)
      nil
      (progn
        (setf (gethash username *registered-players*)
              (list :password-hash (hash-password password)
                    :display-name display-name
                    :created-at (get-universal-time)
                    :last-login (get-universal-time)))
        (setf (gethash username *players-by-username*) player-obj)
        (mud.utils:log-message "New player registered: ~A (~A)" username display-name)
        t)))

(defun validate-login (username password)
  "Validate a player's login credentials.
   Returns the player-info plist if valid, NIL otherwise."
  (let ((player-info (player-exists-p username)))
    (if (and player-info
             (verify-password password (getf player-info :password-hash)))
        (progn
          ;; Update last login
          (setf (getf player-info :last-login) (get-universal-time))
          player-info)
        nil)))

(defun get-player-display-name (username)
  "Get the display name for a registered player."
  (let ((player-info (player-exists-p username)))
    (when player-info
      (getf player-info :display-name))))

(defun update-player-display-name (username new-name)
  "Update a player's display name."
  (let ((player-info (player-exists-p username)))
    (when player-info
      (setf (getf player-info :display-name) new-name)
      t)))

(defun update-player-socket (username socket)
  "Update the socket for a reconnecting player."
  (let ((player-obj (get-player-object username)))
    (when player-obj
      (setf (player-socket player-obj) socket)
      player-obj)))
