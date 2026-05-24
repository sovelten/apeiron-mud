(push #p"./" asdf:*central-registry*)
(asdf:clear-configuration)
(ql:quickload '(:usocket :bordeaux-threads :fiveam))

;; Load just the mud system without starting the server
(ql:quickload :mud)

;; Now load the tests
(ql:quickload :mud/tests)

;; Run the tests
(format t "~%=== Running MUD Tests ===~%~%")
(fiveam:run! 'mud.tests:mud-tests)
(format t "~%=== Tests Complete ===~%~%")

;; Exit cleanly
(sb-ext:exit :code 0)

