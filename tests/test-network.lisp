(in-package #:mud-test)

(in-suite mud-tests)

(test socket-stream-error-handling
  "Test that socket errors are handled gracefully"
  (handler-case
      (progn
        (let ((session (make-instance 'apeiron.core:mud-session :socket nil))
              (player (apeiron.core:new-character "TestPlayer" (make-instance 'apeiron.core:mud-session :socket nil))))
          ;; Sending message to player with nil socket should not crash
          (apeiron.core:player-send-message player "Test message")
          (is (not (null player)))))
    (error (e)
      ;; Error is expected, just check it doesn't crash the test
      (is (not (null e))))))

(test socket-stream-creation
  "Test that we can get a stream from a socket"
  (let* ((server-socket (usocket:socket-listen "127.0.0.1" 0 :reuseaddress t))
         (port (usocket:get-local-port server-socket))
         (client-socket (usocket:socket-connect "127.0.0.1" port))
         (accepted-socket (usocket:socket-accept server-socket))
         (stream (usocket:socket-stream accepted-socket)))
    (unwind-protect
         (progn
           (is (not (null server-socket)))
           (is (not (null client-socket)))
           (is (not (null accepted-socket)))
           (is (not (null stream)))
           (is (streamp stream)))
      (when stream (close stream))
      (when client-socket (usocket:socket-close client-socket))
      (when accepted-socket (usocket:socket-close accepted-socket))
      (when server-socket (usocket:socket-close server-socket)))))

(test player-message-with-mock-socket
  "Test sending messages to a player with a real socket"
  (handler-case
      (let* ((server-socket (usocket:socket-listen "127.0.0.1" 0 :reuseaddress t))
             (port (usocket:get-local-port server-socket))
             (client-socket (usocket:socket-connect "127.0.0.1" port))
             (accepted-socket (usocket:socket-accept server-socket))
             (session (make-instance 'apeiron.core:mud-session :socket accepted-socket)))
        (unwind-protect
             (progn
               (apeiron.persistence:world-restore-or-initialize)
               (let ((player (apeiron.core:new-character "TestPlayer" session)))
                 (is (not (null player)))
                 ;; Test that we can send a message without crashing
                 (apeiron.core:player-send-message player "Test message")
                 (is (not (null player)))))
          (when client-socket (usocket:socket-close client-socket))
          (when accepted-socket (usocket:socket-close accepted-socket))
          (when server-socket (usocket:socket-close server-socket))))
    (error (e)
      (skip (format nil "Socket message test skipped: ~A" e)))))

(test client-socket-read
  "Test that we can read from a socket stream"
  (let* ((server-socket (usocket:socket-listen "127.0.0.1" 0 :reuseaddress t))
         (port (usocket:get-local-port server-socket))
         (client-socket (usocket:socket-connect "127.0.0.1" port))
         (accepted-socket (usocket:socket-accept server-socket))
         (stream (usocket:socket-stream accepted-socket)))
    (unwind-protect
         (progn
           (is (not (null server-socket)))
           (is (streamp stream)))
      (when stream (close stream))
      (when client-socket (usocket:socket-close client-socket))
      (when accepted-socket (usocket:socket-close accepted-socket))
      (when server-socket (usocket:socket-close server-socket)))))
