;;;; mcp/src/mud-client.lisp — MUD telnet client
;;;;
;;;; Connects to a running Apeiron MUD server via telnet, handles
;;;; the initial name prompt and login flow, and provides an API
;;;; for sending commands and receiving cleaned output.
;;;;
;;;; Uses apeiron/telnet for RFC 854-compliant I/O (IAC processing,
;;;; UTF-8 encoding, CR LF line endings) and adds ANSI escape code
;;;; stripping and prompt detection on top.

(in-package #:apeiron-mcp/src/package)

;; ─── Internal: ANSI escape code stripping ──────────────────────────

(defun strip-ansi (text)
  "Remove ANSI escape sequences (SGR colors, cursor movement, etc.)
from TEXT, returning clean plain text.

Handles:
  - CSI sequences:  ESC [ ... <final>   (colors, cursor, clear screen)
  - OSC sequences:  ESC ] ... ST        (terminal title, etc.)
  - Simple ESC:     ESC <char>          (single-char escapes, except CSI/OSC)

The implementation walks the string character-by-character so it has
no regex dependency.  ANSI sequences make up a tiny fraction of MUD
output, so the performance impact is negligible."
  (let* ((len (length text))
         (out (make-array len :element-type 'character :fill-pointer 0))
         (i 0))
    (loop while (< i len) do
      (let ((c (char text i)))
        (if (char= c #\Escape)
            ;; Entered a potential escape sequence
            (let ((next-i (1+ i)))
              (cond
                ((>= next-i len)
                 ;; ESC at end of string — keep as literal
                 (vector-push-extend c out)
                 (setf i next-i))
                ((char= (char text next-i) #\[)
                 ;; CSI: ESC [ ... <final byte in #x40-#x7E>
                 (setf i (+ next-i 1))
                 (loop while (< i len)
                       for ch = (char text i)
                       do (setf i (1+ i))
                       when (<= #x40 (char-code ch) #x7E)
                         return nil))
                ((char= (char text next-i) #\])
                 ;; OSC: ESC ] ... ST (ST = BEL #\Bell or ESC \)
                 (setf i (+ next-i 1))
                 (loop while (< i len)
                       for ch = (char text i)
                       do (setf i (1+ i))
                       when (or (char= ch #\Bell)
                                ;; ESC \ terminator: check the char before \
                                (and (char= ch #\\)
                                     (>= i 2)
                                     (char= (char text (- i 2)) #\Escape)))
                         return nil))
                (t
                 ;; Simple ESC sequence (e.g. ESC c for reset)
                 (setf i (+ next-i 1)))))
            ;; Regular character — keep it
            (progn
              (vector-push-extend c out)
              (incf i)))))
    (coerce out 'string)))

;; ─── Internal: read all available output until the prompt ──────────

(defun %read-until-prompt (conn &key (total-timeout 30) (idle-timeout 1.0))
  "Read from CONN until the MUD prompt (\"> \") is detected and the
connection goes idle.

Returns two values: (output-text . prompt-status)
  output-text: the accumulated text with ANSI codes stripped
  prompt-status: :ok, :timeout, or :disconnected

Strategy:
  The MUD sends output lines terminated by CRLF, followed by the prompt
  \"> \" WITHOUT a trailing CRLF (it uses EOR instead).  Because
  telnet-read-line relies on CRLF to delimit lines, it accumulates \"> \"
  internally but can never return it — the function times out waiting for
  CRLF.  We treat that timeout as the end-of-output signal.  When we have
  received at least one line before the timeout we return :ok; otherwise
  we return :timeout to signal that no output arrived at all."
  (let ((acc (make-array 128 :element-type 'character :fill-pointer 0))
        (deadline (+ (get-internal-real-time)
                     (* total-timeout internal-time-units-per-second)))
        (started nil))
    (loop
      (let ((remaining (/ (- deadline (get-internal-real-time))
                          internal-time-units-per-second)))
        (when (<= remaining 0)
          (return-from %read-until-prompt
            (values (coerce acc 'string)
                    (if started :ok :timeout))))
        (multiple-value-bind (line status)
            (telnet:telnet-read-line conn
                                     :timeout (min idle-timeout remaining))
          (cond
            ;; EOF or connection lost — return what we have
            ((or (eq status :eof) (eq status :connection-lost))
             (return-from %read-until-prompt
               (values (coerce acc 'string) :disconnected)))

            ;; Timeout — no more lines available.  This is the normal
            ;; end-of-output signal: the MUD has sent the prompt (\"> \")
            ;; without CRLF, so telnet-read-line consumed it internally
            ;; and timed out.  When we already received at least one line
            ;; we consider this success.
            ((eq status :timeout)
             (return-from %read-until-prompt
               (values (coerce acc 'string)
                       (if started :ok :timeout))))

            ;; Got a complete line — accumulate it (unless it *is* the
            ;; prompt somehow, e.g. if the server sent CRLF after it)
            (t
             (setf started t)
             (let ((stripped (strip-ansi line)))
               (unless (string= stripped "> ")
                 (when (> (fill-pointer acc) 0)
                   (vector-push-extend #\Newline acc))
                 (loop for c across stripped
                       do (vector-push-extend c acc)))))))))))

;; ─── Internal: read the initial name prompt ──────────────────────

(defun %read-name-prompt (conn)
  "Read the initial connection output from the MUD server until we
see the name prompt.  The MUD asks something like \"What is your name?\"
or \"Enter your name:\".

Returns: the full welcome text including the name prompt."
  (let ((acc (make-array 64 :element-type 'character :fill-pointer 0))
        (deadline (+ (get-internal-real-time)
                     (* 30 internal-time-units-per-second))))
    (loop
      (let ((remaining (- deadline (get-internal-real-time))))
        (when (<= remaining 0)
          (return-from %read-name-prompt
            (values (coerce acc 'string) :timeout)))
        (multiple-value-bind (line status)
            (telnet:telnet-read-line conn
                                     :timeout (float (/ remaining
                                                       internal-time-units-per-second))
                                     :poll-interval 0.2)
          (cond
            ((or (eq status :eof) (eq status :connection-lost))
             (return-from %read-name-prompt
               (values (coerce acc 'string) :disconnected)))
            ((eq status :timeout)
             ;; Keep waiting if we haven't exceeded the deadline
             nil)
            (t
             (let ((stripped (strip-ansi line)))
               (when (> (fill-pointer acc) 0)
                 (vector-push-extend #\Newline acc))
               (loop for c across stripped
                     do (vector-push-extend c acc))
               ;; Detect name prompt heuristically
               (when (or (search "name" stripped :test #'char-equal)
                         (search "enter" stripped :test #'char-equal)
                         (search "who" stripped :test #'char-equal))
                 (return-from %read-name-prompt
                   (values (coerce acc 'string) :ok)))))))))))

;; ─── Public: connect to the MUD ──────────────────────────────────

(defun connect-to-mud (host port player-name)
  "Connect to the Apeiron MUD server at HOST:PORT as PLAYER-NAME.

HOST is a string (e.g. \"localhost\"), PORT is an integer (default 8888),
and PLAYER-NAME is the character name.

Returns three values on success:
  (welcome-text nil :ok)

Returns (nil error-message :error) on failure.

The connection is stored in *MUD-CONNECTION* for use by subsequent
calls to SEND-COMMAND and DISCONNECT-FROM-MUD."
  ;; Close any existing connection first
  (when (and *mud-connection*
             (telnet:telnet-connection-alive-p *mud-connection*))
    (disconnect-from-mud))

  (handler-case
      (let* ((usocket (usocket:socket-connect host port
                                              :element-type 'character))
             (conn (telnet:make-telnet-connection usocket)))

        ;; Read the initial server output / name prompt
        (multiple-value-bind (welcome status)
            (%read-name-prompt conn)
          (unless (eq status :ok)
            (telnet:telnet-connection-close conn)
            (return-from connect-to-mud
              (values nil
                      (format nil "Failed to read name prompt: ~A" status)
                      :error)))

          ;; Send the player name
          (telnet:telnet-write-string conn player-name :end :crlf)

          ;; Read the welcome message and first prompt
          (multiple-value-bind (msg pstatus)
              (%read-until-prompt conn :total-timeout 30)
            (declare (ignore pstatus))

            ;; Combine the name prompt response with the welcome message
            (let ((full-welcome
                   (with-output-to-string (s)
                     (write-string welcome s)
                     (terpri s)
                     (write-string player-name s)
                     (when (> (length msg) 0)
                       (terpri s)
                       (write-string msg s)))))

              ;; Store the connection
              (setf *mud-connection* conn)

              (values full-welcome nil :ok)))))

    (usocket:connection-refused-error (e)
      (declare (ignore e))
      (setf *mud-connection* nil)
      (values nil (format nil "Connection refused: ~A:~D" host port) :error))
    (usocket:ns-host-not-found-error (e)
      (declare (ignore e))
      (values nil (format nil "Host not found: ~A" host) :error))
    (usocket:socket-error (e)
      (declare (ignore e))
      (setf *mud-connection* nil)
      (values nil (format nil "Socket error connecting to ~A:~D" host port) :error))
    (error (e)
      (setf *mud-connection* nil)
      (values nil (format nil "Connection error: ~A" e) :error))))

;; ─── Public: send a command ──────────────────────────────────────

(defun send-command (command-string)
  "Send COMMAND-STRING to the connected MUD server and return the
response text.

COMMAND-STRING is any valid MUD command (look, go north, say hello, etc.).

Returns two values on success:
  (response-text nil)

Returns (nil error-message) on failure or if not connected.

The response is the server output between sending the command and
receiving the next prompt, with ANSI codes stripped."
  (unless (mud-connected-p)
    (return-from send-command
      (values nil "Not connected to MUD. Use mud-connect first.")))

  (handler-case
      (let ((conn *mud-connection*))
        ;; Send the command
        (telnet:telnet-write-string conn command-string :end :crlf)

        ;; Read the response
        (multiple-value-bind (text status)
            (%read-until-prompt conn)
          (case status
            (:ok (values text nil))
            (:timeout (values text "Response may be incomplete (timeout)"))
            (:disconnected
             (setf *mud-connection* nil)
             (values text "Connection lost while reading response"))
            (otherwise (values text nil)))))

    (telnet:telnet-connection-lost (e)
      (declare (ignore e))
      (setf *mud-connection* nil)
      (values nil "Connection to MUD was lost"))
    (error (e)
      (values nil (format nil "Error sending command: ~A" e)))))

;; ─── Public: send an eval command ────────────────────────────────

(defun send-eval (lisp-code)
  "Send a Lisp expression to the MUD's eval command.

LISP-CODE is a string containing a valid Common Lisp expression.
It is sent as: eval <lisp-code>

The MUD's eval command executes the code in the APEIRON.EVAL package
with ME (current character), HERE (current room), and WORLD (the
mud-world instance) bound.

Returns two values on success:
  (result-text nil)

Returns (nil error-message) on failure."
  (send-command (format nil "eval ~A" lisp-code)))

;; ─── Public: disconnect ──────────────────────────────────────────

(defun disconnect-from-mud ()
  "Disconnect from the MUD server gracefully.

Sends the 'quit' command and closes the telnet connection.
Returns two values: (message nil) on success, (nil error) on failure."
  (unless (mud-connected-p)
    (setf *mud-connection* nil)
    (return-from disconnect-from-mud
      (values "Not connected" nil)))

  (handler-case
      (let ((conn *mud-connection*))
        ;; Try to send quit gracefully
        (ignore-errors
          (telnet:telnet-write-string conn "quit" :end :crlf)
          (sleep 0.1))
        (telnet:telnet-connection-close conn)
        (setf *mud-connection* nil)
        (values "Disconnected from MUD" nil))
    (error (e)
      (setf *mud-connection* nil)
      (values nil (format nil "Error during disconnect: ~A" e)))))

;; ─── Public: connection status ───────────────────────────────────

(defun connection-status ()
  "Return a human-readable description of the current connection state.

Returns a string suitable for display to the user."
  (if (mud-connected-p)
      "Connected to Apeiron MUD server."
      "Not connected to MUD. Use mud-connect to connect."))
