(push #p"./" asdf:*central-registry*)
(ql:quickload :mud)
(mud:start-mud-server)
