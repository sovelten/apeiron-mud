(push #p"./" asdf:*central-registry*)
(ql:quickload :mud)

;; Check command-line options to force a new world
(let ((force-new (member "--force-new-world" sb-ext:*posix-argv* :test #'string-equal)))
  (mud:start-mud-server :force-new force-new))

;; Keep the main thread alive while server is running
(loop while mud:*server-running*
      do (sleep 1))
