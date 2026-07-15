;;;;
;;;; apeiron-mcp.asd — MCP server for the Apeiron MUD
;;;;
;;;; Provides a JSON-RPC 2.0 MCP server over stdio that allows an LLM
;;;; to connect to a running Apeiron MUD server and interact as a
;;;; player character.
;;;;
;;;; Architecture:
;;;;   tools.lisp        — MCP tool definitions (mud-connect, mud-send, etc.)
;;;;   mud-client.lisp   — Telnet client backed by apeiron.telnet
;;;;   server.lisp       — JSON-RPC 2.0 / MCP protocol over stdio

(defsystem "apeiron-mcp"
  :version "0.1.0"
  :description "MCP server that connects an LLM to the Apeiron MUD as a player."
  :author "Sophia Velten"
  :license "MIT"
  :depends-on ("apeiron/telnet"
               "bordeaux-threads"
               "hunchentoot"
               "usocket"
               "yason")
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "mud-client" :depends-on ("package"))
                 (:file "tools" :depends-on ("package" "mud-client"))
                 (:file "server" :depends-on ("package" "tools"))
                 (:file "http-server" :depends-on ("package" "server")))))
  :build-operation program-op
  :build-pathname "apeiron-mcp"
  :entry-point "apeiron-mcp/src/package:main")
