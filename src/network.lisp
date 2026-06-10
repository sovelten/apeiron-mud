(in-package #:mud)

(defvar *server-running* nil)
(defvar *server-socket* nil)
(defvar *acceptance-thread* nil
  "The thread handling incoming connections")
(defvar *player-threads* (make-hash-table :test #'equal))
(defvar *server-lock* (bordeaux-threads:make-lock "server-lock"))

(defun read-line-with-timeout (socket &optional (timeout 300))
  "Read a line from socket stream with a timeout in seconds.
   Returns (values line status), where status is nil for success,
   :timeout for timeout, and :eof for connection closed."
  (if (null socket)
      (values nil :eof)
      (let ((ready (handler-case (usocket:wait-for-input socket :timeout timeout :ready-only t)
                     (error () nil))))
        (if (null ready)
            (values nil :timeout)
            (let ((stream (handler-case (usocket:socket-stream socket) (error () nil))))
              (if (null stream)
                  (values nil :eof)
                  (handler-case
                      (let ((line (read-line stream nil nil)))
                        (if line
                            (values line nil)
                            (values nil :eof)))
                    (error (e)
                      (values nil e)))))))))

(defun send-keepalive (socket)
  "Send a harmless Telnet NOP (No Operation) command to keep the connection alive.
   This complies with RFC 854 and is ignored by compliant Telnet clients without shifting the cursor.
   If the socket's connection has been lost, this write or its flush will signal an error."
  (when socket
    (let ((stream (usocket:socket-stream socket)))
      (mud.utils:log-message "Staying alive with Telnet NOP...")
      (when stream
        (force-output stream)
        #+sbcl
        (let* ((fd (sb-sys:fd-stream-fd stream))
               (octets (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(255 241)))
               (sap (sb-sys:vector-sap octets)))
          (sb-unix:unix-write fd sap 0 2))
        #-sbcl
        (progn
          (write-char (code-char 255) stream)
          (write-char (code-char 241) stream)
          (force-output stream))))))

(defun read-line-with-timeout-loop (socket &key (poll-interval 30) (keepalive-func #'send-keepalive))
  "Read a line from socket stream by polling with a short timeout (POLL-INTERVAL).
   If polling times out, it invokes KEEPALIVE-FUNC (e.g., to send a keepalive probe)
   to verify if the connection is still alive, and then continues waiting.
   This allows players to stay connected indefinitely while actively detecting broken connections."
  (loop
     (multiple-value-bind (line status) (read-line-with-timeout socket poll-interval)
       (cond
         ((null status)
          (return (values line nil)))
         ((eq status :timeout)
          (if keepalive-func
              (handler-case
                  (progn
                    (funcall keepalive-func socket)
                    nil)
                (error (e)
                  (return (values nil e))))
              nil))
         (t
          (return (values nil status)))))))

(defun ask-name (session default)
  (session-send-message session "What is your name?")
  (let ((socket (session-socket session)))
    (if (null socket)
        default
        (progn
          (session-send-prompt session)
          (multiple-value-bind (line status) (read-line-with-timeout socket 300)
            (if (and line (null status))
                (let ((trimmed (string-trim '(#\Return #\Newline) line)))
                  (if (and trimmed (> (length trimmed) 0))
                      trimmed
                      default))
                default))))))

(defun handle-client (session)
  "Main loop for handling a client connection."
  (let* ((guest-name (format nil "Guest~D" (random 10000)))
         (char-name (ask-name session guest-name))
         (character (new-character char-name session)))
    (mud.utils:log-message "New connection: ~A" char-name)
    (world-new-character character)
    (session-send-message session (room-describe (object-location character)))
    (session-send-message session "Welcome to the MUD!")
    (handler-case
        (let ((socket (session-socket session)))
          (loop while *server-running*
                do
                   (handler-case
                       (progn
                         ;; Send prompt
                         (session-send-prompt session)

                         (multiple-value-bind (line status) (read-line-with-timeout-loop socket)
                           (cond
                             ((eq status :timeout)
                              (session-send-message session "Timed out due to inactivity.")
                              (mud.utils:log-message "Client ~A timed out due to inactivity" char-name)
                              (return))
                             ((or (eq status :eof) (typep status 'error))
                              (mud.utils:log-message "Client ~A disconnected ~A" char-name status)
                              (return))
                             (line
                              (let ((trimmed (string-trim '(#\Return #\Newline) line)))
                                (when (and trimmed (> (length trimmed) 0))
                                  (process-command character trimmed))))
                             (t
                              (return)))))
                     (end-of-file ()
                       ;; Connection closed by client
                       (mud.utils:log-message "Client ~A disconnected end-of-file" char-name)
                       (return))
                     (error (e)
                       ;; Check if this is a "broken pipe" or similar connection error
                       (let ((error-str (format nil "~A" e)))
                         (if (or (search "Broken pipe" error-str)
                                 (search "closed" error-str))
                             ;; Connection error, exit gracefully
                             (progn
                               (mud.utils:log-message "Client ~A connection lost" char-name)
                               (return))
                             ;; Other error, log it
                             (progn
                               (mud.utils:log-error "Error in client handler: ~A" e)
                               (return))))))))
      (error (e)
        (mud.utils:log-error "Client handler error for ~A: ~A" char-name e))))

  ;; Cleanup when disconnected
  (let ((session-id (session-id session)))
    (mud.utils:log-message "Attempting to remove thread for session ~A" session-id)
    (remhash session-id *player-threads*)
    (when (session-character session)
      (remove-character (session-character session)))
    (session-disconnect session)))

(defun accept-connections ()
  "Accept incoming client connections."
  (handler-case
      (loop while *server-running*
            do
               (handler-case
                   (let ((client-socket (usocket:socket-accept *server-socket*)))
                     (when client-socket
                       (if (not *server-running*)
                           (usocket:socket-close client-socket)
                           (let ((session (create-session client-socket)))
                             ;; Start session thread
                             (let ((thread (bordeaux-threads:make-thread
                                            (lambda () (handle-client session))
                                            :name (format nil "session-~A" (session-id session)))))
                               (mud.utils:log-message "Thread for session ~A created" (session-id session))
                               (setf (gethash (session-id session) *player-threads*) thread))))))
                 (usocket:timeout-error ()
                   ;; Just a timeout, continue accepting
                   nil)
                 (error (e)
                   ;; If the server is stopping, ignore socket errors from closed listening socket
                   (when *server-running*
                     (mud.utils:log-error "Error accepting connection: ~A" e)))))
    (error (e)
      (when *server-running*
        (mud.utils:log-error "Accept connections error: ~A" e)))))

(defun start-mud-server (&key (host *server-host*) (port *server-port*) force-new)
  "Start the MUD server."
  (bordeaux-threads:with-lock-held (*server-lock*)
    (if *server-running*
        (progn
          (mud.utils:log-error "Server is already running!")
          (return-from start-mud-server nil))
        (progn
          ;; Initialize world
          (world-restore-or-initialize :force-new force-new)
          (setf *server-socket*
                (usocket:socket-listen host port :reuse-address t :backlog 5))
          (setf *server-running* t)
          (mud.utils:log-message "MUD Server started on ~A:~D" host port)
          (setf *acceptance-thread*
                (bordeaux-threads:make-thread #'accept-connections :name "accept-connections"))
          t))))

(defun stop-mud-server ()
  "Stop the MUD server."
  (bordeaux-threads:with-lock-held (*server-lock*)
    (when *server-running*
      (setf *server-running* nil)
      
      ;; Fire a dummy connection to unblock socket-accept if it is blocked
      (when *server-socket*
        (handler-case
            (let ((port (usocket:get-local-port *server-socket*)))
              (when port
                (let ((dummy (usocket:socket-connect "127.0.0.1" port)))
                  (usocket:socket-close dummy))))
          (error () nil)))
      
      ;; Close server socket first (this will unblock socket-accept)
      (when *server-socket*
        (handler-case
            (usocket:socket-close *server-socket*)
          (error (e)
            (mud.utils:log-error "Error closing server socket: ~A" e)))
        (setf *server-socket* nil))
      
      ;; Wait for acceptance thread to exit
      (when *acceptance-thread*
        (handler-case
            (bordeaux-threads:join-thread *acceptance-thread*)
          (error (e)
            (mud.utils:log-error "Error joining acceptance thread: ~A" e)))
        (setf *acceptance-thread* nil))
      
      ;; Disconnect all players
      (dolist (player (characters))
        (progn (remove-character player)
               (session-disconnect (character-session player))))
      
      (mud.utils:log-message "MUD Server stopped")
      t)))

(defun get-server-status ()
  "Get the current status of the server."
  (format nil "Server running: ~A~%Players online: ~D~%Rooms in world: ~D~%"
          (if *server-running* "Yes" "No")
          (total-players)
          (total-rooms)))
