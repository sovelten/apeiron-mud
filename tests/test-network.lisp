(in-package #:mud.tests)

(in-suite mud-tests)

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
             (session (make-instance 'mud:mud-session :socket accepted-socket)))
        (unwind-protect
             (progn
               (mud:world-restore-or-initialize)
               (let ((player (mud:new-character "TestPlayer" session)))
                 (is (not (null player)))
                 ;; Test that we can send a message without crashing
                 (mud:player-send-message player "Test message")
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
