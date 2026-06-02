(in-package #:mud)

(defvar *server-thread* nil
  "The background thread running the MUD server")

;; Entry point to start the MUD server

(defun start (&key (background t))
  "Start the MUD server. If BACKGROUND is T (default), runs in a background thread.
   Returns T if server started successfully, NIL otherwise."
  (if background
      ;; Start in background thread
      (unless *server-thread*
        (when (start-mud-server)
          (setf *server-thread* 
                (bordeaux-threads:make-thread 
                 (lambda ()
                   ;; Keep thread alive while server is running
                   (loop while *server-running*
                         do (sleep 1))
                   ;; Server stopped, clear thread reference
                   (setf *server-thread* nil))
                 :name "mud-main"))
          t))
      ;; Start in foreground (blocking)
      (when (start-mud-server)
        (loop while *server-running*
              do (sleep 1)))))

(defun status ()
  "Print the server status."
  (format t "~A" (get-server-status)))

(defun stop ()
  "Stop the MUD server."
  (stop-mud-server))
