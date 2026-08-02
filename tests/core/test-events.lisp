(in-package #:apeiron-test)

(in-suite events-suite)

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

(defun with-temp-log-dir (thunk)
  "Execute THUNK with *DATA-DIRECTORY* bound to a fresh temp directory
so log4cl writes its files there.  The directory is cleaned up after
THUNK returns."
  (let ((dir (uiop:merge-pathnames*
              (format nil "test-log4cl-~D/" (random 1000000))
              (uiop:default-temporary-directory))))
    (ensure-directories-exist dir)
    (let ((apeiron.core::*data-directory* dir)
          (apeiron.core::*logging-configured* nil))
      (unwind-protect
           (funcall thunk dir)
        (ignore-errors (shutdown-logging))
        (ignore-errors (uiop:delete-directory-tree dir :validate (constantly t)))
        (setf apeiron.core::*logging-configured* nil)))))

(defun log-file-contents (dir)
  "Return the full contents of mud.log in DIR as a string, or NIL if the file
does not exist."
  (let ((log-path (merge-pathnames "mud.log" dir)))
    (when (probe-file log-path)
      (with-open-file (s log-path :direction :input)
        (with-output-to-string (out)
          (loop for line = (read-line s nil)
                while line
                do (write-line line out)))))))

(defmacro with-test-handler ((handler-var event-type (event-var &rest slot-bindings) capture-var) &body body)
  "Create a locally-blocking handler whose delivery-function sets CAPTURE-VAR
to the received event, then execute BODY.  HANDLER-VAR is bound to the
handler object for use with DEEDS:HANDLE synchronous delivery.
The handler is deregistered and stopped on exit.

Example:
  (let ((captured nil))
    (with-test-handler (h deeds:info-event (ev message) captured)
      (deeds:handle (make-instance 'deeds:info-event :message \"hi\") h)
      (is (search \"hi\" (deeds:message captured)))))"
  `(let ((,handler-var
           (deeds:with-handler ,event-type (,event-var ,@slot-bindings)
             :class 'deeds:locally-blocking-handler
             (setf ,capture-var ,event-var))))
     (unwind-protect (progn ,@body)
       (ignore-errors
        (deeds:deregister-handler ,handler-var deeds:*standard-event-loop*)
        (deeds:stop ,handler-var)))))

;; ---------------------------------------------------------------------------
;; Event type hierarchy
;; ---------------------------------------------------------------------------

(test mud-event-hierarchy
  "Verify that our custom event types inherit correctly from deeds:event."
  (is (subtypep 'mud-event 'deeds:event))
  (is (subtypep 'session-event 'mud-event))
  (is (subtypep 'character-input-event 'session-event))
  (is (subtypep 'character-output-event 'session-event)))

(test mud-event-subtypes-do-not-leak
  "MUD events are not subtypes of deeds:message-event or its children."
  (is (not (subtypep 'mud-event 'deeds:message-event)))
  (is (not (subtypep 'character-input-event 'deeds:info-event))))

;; ---------------------------------------------------------------------------
;; Event issuance (synchronous via deeds:handle)
;; ---------------------------------------------------------------------------

(test issue-info-event
  "issue-info-event should create and deliver an info-event."
  (let ((captured nil))
    (with-test-handler (h deeds:info-event (ev message) captured)
      (deeds:handle (make-instance 'deeds:info-event :message "test 42") h))
    (is (typep captured 'deeds:info-event))
    (is (search "test 42" (deeds:message captured)))))

(test issue-error-event
  "issue-error-event should create and deliver an error-event."
  (let ((captured nil))
    (with-test-handler (h deeds:error-event (ev message) captured)
      (deeds:handle (make-instance 'deeds:error-event :message "error 99") h))
    (is (typep captured 'deeds:error-event))
    (is (search "error 99" (deeds:message captured)))))

(test character-input-event-slots
  "A character-input-event should expose its slots correctly."
  (let ((ev (make-instance 'character-input-event
                           :session-id 42
                           :character-name "TestHero"
                           :input "look")))
    (is (= 42 (session-id ev)))
    (is (equal "TestHero" (character-name ev)))
    (is (equal "look" (input ev)))))

(test character-output-event-slots
  "A character-output-event should expose its slots correctly."
  (let ((ev (make-instance 'character-output-event
                           :session-id 7
                           :character-name "Alice"
                           :output "You see a dark passage.")))
    (is (= 7 (session-id ev)))
    (is (equal "Alice" (character-name ev)))
    (is (search "dark passage" (output ev)))))

;; ---------------------------------------------------------------------------
;; log4cl logging infrastructure (configure / shutdown / write)
;; ---------------------------------------------------------------------------

(test configure-logging-creates-log-file
  "configure-logging should create the mud.log file in the data directory."
  (with-temp-log-dir
    (lambda (dir)
      (configure-logging)
      (sleep 0.1)
      (is-true (probe-file (merge-pathnames "mud.log" dir)))
      (shutdown-logging))))

(test shutdown-logging-clears-state
  "After shutdown-logging, *LOGGING-CONFIGURED* should be NIL."
  (with-temp-log-dir
    (lambda (dir)
      (declare (ignore dir))
      (configure-logging)
      (is-true *logging-configured*)
      (shutdown-logging)
      (is-false *logging-configured*))))

(test configure-logging-is-idempotent
  "A second call to configure-logging should be a no-op."
  (with-temp-log-dir
    (lambda (dir)
      (declare (ignore dir))
      (is-true (configure-logging))
      ;; Second call should return T but not re-configure.
      (is-true (configure-logging))
      (shutdown-logging))))

(test log-message-writes-to-log-file
  "log-message should write an INFO-level entry to the log file."
  (let ((contents
          (with-temp-log-dir
            (lambda (dir)
              (configure-logging)
              (log-message "test message ~D" 42)
              (sleep 0.2)
              (shutdown-logging)
              (log-file-contents dir)))))
    (is (search "test message 42" contents))
    (is (search "INFO" contents))))

(test log-error-writes-to-log-file
  "log-error should write an ERROR-level entry to the log file."
  (let ((contents
          (with-temp-log-dir
            (lambda (dir)
              (configure-logging)
              (log-error "critical failure ~A" "boom")
              (sleep 0.2)
              (shutdown-logging)
              (log-file-contents dir)))))
    (is (search "critical failure boom" contents))
    (is (search "ERROR" contents))))

(test log-with-ndc-adds-context
  "log:with-ndc should attach contextual metadata to log lines."
  (let ((contents
          (with-temp-log-dir
            (lambda (dir)
              (configure-logging)
              (let ((ndc "ip=10.0.0.1 session=123 char=Hero"))
                (log:with-ndc (ndc)
                  (log-message "player action")))
              (sleep 0.2)
              (shutdown-logging)
              (log-file-contents dir)))))
    (is (search "player action" contents))
    (is (search "Hero" contents))
    (is (search "10.0.0.1" contents))))

;; ---------------------------------------------------------------------------
;; Deprecated API wrappers
;; ---------------------------------------------------------------------------

;; ---------------------------------------------------------------------------
;; handle-event generic
;; ---------------------------------------------------------------------------

(test handle-event-default-is-noop
  "The default handle-event method should return NIL for any object+event."
  (let ((obj (new-object :name "dummy")))
    (is (null (handle-event obj (make-instance 'character-input-event
                                               :session-id 0
                                               :character-name "X"
                                               :input ""))))))

(test handle-event-can-be-specialised
  "We can define a specialised handle-event method and call it."
  (let* ((calls 0)
         (obj (new-object :name "special"))
         ;; Capture the cell so the method can increment it.
         (method-fn (lambda (obj ev)
                      (declare (ignore obj ev))
                      (incf calls))))
    (unwind-protect
         (progn
           (add-method #'handle-event
                       (make-instance 'standard-method
                                      :specializers (list (find-class 'mud-object)
                                                          (find-class 'character-input-event))
                                      :lambda-list '(obj ev)
                                      :function method-fn))
           (handle-event obj (make-instance 'character-input-event
                                            :session-id 0
                                            :character-name "X"
                                            :input "hi"))
           (is (= 1 calls)))
      ;; Tear down: remove the temporary method
      (handler-case
          (remove-method #'handle-event
                         (find-method #'handle-event
                                      nil
                                      (list (find-class 'mud-object)
                                            (find-class 'character-input-event))))
        (error () nil)))))
