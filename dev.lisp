(ql:quickload :cl-mcp)
(cl-mcp:start-http-server :port 3000)

;; Register this directory with ASDF so it finds our .asd files regardless
;; of Quicklisp's local-projects cache or symlinks.
(let ((project-dir (make-pathname :name nil :type nil :defaults *load-truename*)))
  (pushnew project-dir asdf:*central-registry* :test #'equal))

(ql:quickload :apeiron)
(ql:quickload :apeiron-test)

;; (cl-mcp:initialize-pool) to reinitialize-pool if something goes wrong with cl-mcp (I think)
