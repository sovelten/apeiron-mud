(push #p"./" asdf:*central-registry*)
(ql:quickload :apeiron)

;; Check command-line options to force a new world
(let ((force-new (member "--force-new-world" sb-ext:*posix-argv*
                         :test #'string-equal)))
  ;; Look for TLS certificate/key in the project root
  (let ((cert-path (merge-pathnames "cert.pem" (uiop:getcwd)))
        (key-path (merge-pathnames "key.pem" (uiop:getcwd))))
    (when (and (probe-file cert-path) (probe-file key-path))
      (setf mud:*server-ssl-certificate* (namestring cert-path)
            mud:*server-ssl-key* (namestring key-path))
      (format t "~&TLS cert found: ~A~%" cert-path)))
  (mud:start-mud-server :force-new force-new))

;; Keep the main thread alive while server is running
(loop while mud:*server-running*
      do (sleep 1))
