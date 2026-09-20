(in-package #:apeiron-test)

(in-suite server-suite)

;; ─── Mock telnet connection ─────────────────────────────────────────────────

(defclass mock-telnet-connection (telnet:telnet-connection)
  ((char-queue
    :initform nil
    :accessor mock-conn-char-queue
    :documentation "List of (char . status) conses consumed by telnet-read-char.")
   (sent-bytes
    :initform (make-array 0 :adjustable t :fill-pointer 0)
    :accessor mock-conn-sent-bytes
    :documentation "Flattened vector of all bytes sent via telnet-write-raw."))
  (:default-initargs
   :usocket nil
   :raw-stream (make-broadcast-stream)
   :protocol (make-instance 'telnet:telnet-protocol))
  (:documentation "Mock telnet connection for unit-testing session I/O."))

(defmethod telnet:telnet-read-char ((conn mock-telnet-connection) &key timeout)
  (declare (ignore timeout))
  (let ((queue (mock-conn-char-queue conn)))
    (if queue
        (let ((pair (pop (mock-conn-char-queue conn))))
          (values (car pair) (cdr pair)))
        (values nil :timeout))))

(defmethod telnet:telnet-write-raw ((conn mock-telnet-connection) byte-vector)
  (loop for b across byte-vector
        do (vector-push-extend b (mock-conn-sent-bytes conn))))

;; ─── Mock helpers ───────────────────────────────────────────────────────────

(defun mock-conn-enqueue (conn char &optional (status nil))
  (setf (mock-conn-char-queue conn)
        (append (mock-conn-char-queue conn) (list (cons char status)))))

(defun mock-conn-enqueue-string (conn string)
  (loop for c across string do (mock-conn-enqueue conn c))
  (mock-conn-enqueue conn #\Return))

(defun mock-conn-enqueue-timeout (conn &optional (n 1))
  (dotimes (i n) (mock-conn-enqueue conn nil :timeout)))

(defun mock-conn-sent-commands (conn)
  "Return list of (CMD OPTION) for IAC WILL/WONT/DO/DONT commands sent."
  (let ((bytes (mock-conn-sent-bytes conn))
        (cmds nil))
    (loop for i from 0 below (1- (length bytes))
          when (= (aref bytes i) telnet:iac)
          do (let ((cmd (aref bytes (1+ i))))
               (when (member cmd (list telnet:will telnet:wont
                                       telnet:do telnet:dont))
                 (push (list cmd (aref bytes (+ i 2))) cmds)
                 (incf i 2))))
    (nreverse cmds)))

(defun mock-conn-sent-asterisk-count (conn)
  (loop for b across (mock-conn-sent-bytes conn) count (= b 42)))

(defun make-mock-telnet-session (&key char-queue)
  (let* ((conn (make-instance 'mock-telnet-connection))
         (session (make-instance 'telnet-session
                                 :id (make-id)
                                 :telnet-conn conn)))
    (when char-queue
      (setf (mock-conn-char-queue conn) char-queue))
    session))

;; ─── Tests ─────────────────────────────────────────────────────────────────

(test telnet-read-secret-sends-will-echo
  "IAC WILL ECHO is sent before reading."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (mock-conn-enqueue conn #\a)
    (mock-conn-enqueue conn #\Return)
    (mud-read-secret session :timeout 1)
    (let ((cmds (mock-conn-sent-commands conn)))
      (is (member (list telnet:will 1) cmds :test #'equal)
          "Should send IAC WILL ECHO (option 1)"))))

(test telnet-read-secret-sends-wont-echo-after
  "IAC WONT ECHO is sent after reading."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (mock-conn-enqueue conn #\a)
    (mock-conn-enqueue conn #\Return)
    (mud-read-secret session :timeout 1)
    (let ((cmds (mock-conn-sent-commands conn)))
      (is (find (list telnet:wont 1) cmds :test #'equal)
          "Should send IAC WONT ECHO after reading"))))

(test telnet-read-secret-echo-state-cleaned-up
  "ECHO wanted/enabled flags are cleared after reading."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session))
         (protocol (telnet:telnet-conn-protocol conn))
         (echo-state (telnet::ensure-option-state protocol :local
                                                  telnet:+telnet-opt-echo+)))
    (mock-conn-enqueue conn #\a)
    (mock-conn-enqueue conn #\Return)
    (mud-read-secret session :timeout 1)
    (is (not (telnet::telnet-option-state-wanted echo-state))
        "ECHO wanted should be cleared")
    (is (not (telnet::telnet-option-state-enabled echo-state))
        "ECHO enabled should be cleared")))

(test telnet-read-secret-returns-password
  "Returns the typed characters."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (mock-conn-enqueue conn #\s)
    (mock-conn-enqueue conn #\e)
    (mock-conn-enqueue conn #\c)
    (mock-conn-enqueue conn #\Return)
    (multiple-value-bind (line status)
        (mud-read-secret session :timeout 1)
      (is (null status))
      (is (equal "sec" line)))))

(test telnet-read-secret-echoes-asterisks
  "One * echoed per character typed."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (mock-conn-enqueue conn #\x)
    (mock-conn-enqueue conn #\y)
    (mock-conn-enqueue conn #\z)
    (mock-conn-enqueue conn #\Return)
    (mud-read-secret session :timeout 1)
    (is (= 3 (mock-conn-sent-asterisk-count conn)))))

(test telnet-read-secret-empty-password
  "Empty password (just CR) returns empty string."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (mock-conn-enqueue conn #\Return)
    (multiple-value-bind (line status)
        (mud-read-secret session :timeout 1)
      (is (null status))
      (is (equal "" line))
      (is (= 0 (mock-conn-sent-asterisk-count conn))))))

(test telnet-read-secret-survives-timeouts
  "Keeps polling through :timeout responses."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (mock-conn-enqueue-timeout conn 3)
    (mock-conn-enqueue conn #\p)
    (mock-conn-enqueue conn #\w)
    (mock-conn-enqueue conn #\Return)
    (multiple-value-bind (line status)
        (mud-read-secret session :timeout 1)
      (is (null status))
      (is (equal "pw" line)))))

(test telnet-read-secret-handles-lf
  "LF also ends the line."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (mock-conn-enqueue conn #\a)
    (mock-conn-enqueue conn #\Newline)
    (multiple-value-bind (line status)
        (mud-read-secret session :timeout 1)
      (is (null status))
      (is (equal "a" line)))))

(test telnet-read-secret-consumes-trailing-lf
  "CR+LF: the trailing LF is consumed, not left in the queue."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (mock-conn-enqueue conn #\x)
    (mock-conn-enqueue conn #\Return)
    (mock-conn-enqueue conn #\Newline)
    (multiple-value-bind (line status)
        (mud-read-secret session :timeout 1)
      (is (null status))
      (is (equal "x" line)))
    (is (null (mock-conn-char-queue conn))
        "Trailing LF should be consumed, queue empty")))

(test telnet-read-secret-no-conn-returns-eof
  "Returns :eof when there is no connection."
  (let ((session (make-instance 'telnet-session :id (make-id) :telnet-conn nil)))
    (multiple-value-bind (line status)
        (mud-read-secret session)
      (is (null line))
      (is (eq status :eof)))))

(test session-alive-p-reports-disconnected-session-dead
  "Regression: SESSION-ALIVE-P must report a telnet session as dead once
SESSION-DISCONNECT has closed its connection, so HANDLE-CLIENT's game loop
stops polling it (and never touches the freed transport)."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session)))
    (is-true (session-alive-p session)
             "A freshly connected session should be alive")
    (session-disconnect session)
    (is-false (telnet:telnet-connection-alive-p conn)
              "session-disconnect should close the telnet connection")
    (is-false (session-alive-p session)
              "A disconnected session must report itself dead")))

(test session-alive-p-default-true-for-base-session
  "The base MUD-SESSION (no transport) is always considered alive."
  (is-true (session-alive-p (new-session))))

;; ─── GMCP character sync ────────────────────────────────────────────────────

(defun enable-mock-gmcp (conn)
  "Enable GMCP on CONN's protocol, as if the client answered DO GMCP."
  (let ((protocol (telnet:telnet-conn-protocol conn)))
    (setf (telnet::telnet-option-state-enabled
           (telnet::ensure-option-state protocol :local telnet:+telnet-opt-gmcp+))
          t)))

(test session-sync-character-sends-gmcp-vitals-and-stats
  "SESSION-SYNC-CHARACTER emits Char.Vitals and Char.Stats once GMCP is enabled."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session))
         (character (new-character "Tester" session)))
    (enable-mock-gmcp conn)
    (session-sync-character session character)
    (let ((text (map 'string #'code-char (mock-conn-sent-bytes conn))))
      (is-true (search "Char.Vitals" text) "Should send Char.Vitals")
      (is-true (search "\"hp\":100" text) "Vitals should carry current hp")
      (is-true (search "\"maxhp\":100" text) "Vitals should carry max hp")
      (is-true (search "Char.Stats" text) "Should send Char.Stats")
      (is-true (search "\"str\":10" text) "Stats should carry strength")
      (is-true (search "\"sta\":10" text) "Stats should carry stamina")
      (is-true (search "\"int\":10" text) "Stats should carry intelligence"))))

(test session-sync-character-writes-nothing-without-gmcp
  "SESSION-SYNC-CHARACTER is a no-op when GMCP was not negotiated."
  (let* ((session (make-mock-telnet-session))
         (conn (session-telnet-connection session))
         (character (new-character "Tester" session)))
    (session-sync-character session character)
    (is (= 0 (length (mock-conn-sent-bytes conn)))
        "No bytes should be written when GMCP is not negotiated")))

(test session-sync-character-default-method-is-noop
  "The base MUD-SESSION never sends protocol messages."
  (is (null (session-sync-character (new-session) nil))))
