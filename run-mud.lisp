(push #p"./" asdf:*central-registry*)
(ql:quickload :mud)
(mud:start-mud-server)
;; Keep the main thread alive while server is running
(loop while mud:*server-running*
      do (sleep 1))
