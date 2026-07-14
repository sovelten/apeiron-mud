(in-package #:apeiron-test)

(in-suite events-suite)

;; ---------------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------------

(defun with-temp-log-file (thunk)
  "Execute THUNK with *EVENT-LOG-FILE* bound to a fresh temp file.
THUNK receives the log-path as its sole argument and should return the
value to propagate.  The log file is cleaned up after THUNK returns."
  (let ((log-path (uiop:merge-pathnames*
                   (format nil "test-events-~D.log" (random 1000000))
                   (uiop:default-temporary-directory))))
    (setf *event-log-file* log-path)
    (when (probe-file log-path)
      (delete-file log-path))
    (unwind-protect
         (funcall thunk log-path)
      (ignore-errors (stop-event-logging))
      (ignore-errors (delete-file log-path))
      (setf *event-log-file* nil))))

(defun log-file-contents (log-path)
  "Return the full contents of LOG-PATH as a string, or NIL if the file
does not exist."
  (when (probe-file log-path)
    (with-open-file (s log-path :direction :input)
      (let ((buf (make-string (file-length s))))
        (read-sequence buf s)
        buf))))

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
  (is (subtypep 'player-input-event 'session-event))
  (is (subtypep 'player-output-event 'session-event)))

(test mud-event-subtypes-do-not-leak
  "MUD events are not subtypes of deeds:message-event or its children."
  (is (not (subtypep 'mud-event 'deeds:message-event)))
  (is (not (subtypep 'player-input-event 'deeds:info-event))))

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

(test player-input-event-slots
  "A player-input-event should expose its slots correctly."
  (let ((ev (make-instance 'player-input-event
                           :session-id 42
                           :character-name "TestHero"
                           :input "look")))
    (is (= 42 (session-id ev)))
    (is (equal "TestHero" (character-name ev)))
    (is (equal "look" (input ev)))))

(test player-output-event-slots
  "A player-output-event should expose its slots correctly."
  (let ((ev (make-instance 'player-output-event
                           :session-id 7
                           :character-name "Alice"
                           :output "You see a dark passage.")))
    (is (= 7 (session-id ev)))
    (is (equal "Alice" (character-name ev)))
    (is (search "dark passage" (output ev)))))

;; ---------------------------------------------------------------------------
;; File-logging infrastructure (start / stop / write)
;; ---------------------------------------------------------------------------

(test start-stop-event-logging
  "Start and stop event logging; verify log file is created and flushed."
  (with-temp-log-file
    (lambda (lp)
      (declare (ignore lp))
      (start-event-logging :log-file *event-log-file*)
      (is (probe-file *event-log-file*))
      (stop-event-logging)
      ;; After stop, *event-log-file* should be NIL
      (is (null *event-log-file*)))))

(test log-file-contains-system-start-stop-markers
  "After start and stop, the log file must contain both markers."
  (let ((contents
          (with-temp-log-file
            (lambda (lp)
              (start-event-logging :log-file *event-log-file*)
              (stop-event-logging)
              (log-file-contents lp)))))
    (is (search "=== Event logging started ===" contents))
    (is (search "=== Event logging stopped ===" contents))))

(test log-file-captures-info-event
  "An info-event issued while logging is active should appear in the log."
  (let ((contents
          (with-temp-log-file
            (lambda (lp)
              (start-event-logging :log-file *event-log-file*)
              (issue-info-event "hello world")
              ;; Give the queued handler a moment to process.
              (sleep 0.2)
              (stop-event-logging)
              (log-file-contents lp)))))
    (is (search "INFO hello world" contents))))

(test log-file-captures-error-event
  "An error-event issued while logging is active should appear in the log."
  (let ((contents
          (with-temp-log-file
            (lambda (lp)
              (start-event-logging :log-file *event-log-file*)
              (issue-error-event "something broke")
              (sleep 0.2)
              (stop-event-logging)
              (log-file-contents lp)))))
    (is (search "ERROR something broke" contents))))

(test log-file-captures-player-input-event
  "A player-input-event issued while logging is active should appear in the log."
  (let ((contents
          (with-temp-log-file
            (lambda (lp)
              (start-event-logging :log-file *event-log-file*)
              (issue-player-input-event 1 "Hero" "attack goblin")
              (sleep 0.2)
              (stop-event-logging)
              (log-file-contents lp)))))
    (is (search "INPUT attack goblin" contents))
    (is (search "session=1" contents))
    (is (search "char=Hero" contents))))

(test log-file-does-not-capture-player-output-event
  "A player-output-event issued while logging is active should NOT appear
in the log — output events are intentionally excluded to reduce log volume."
  (let ((contents
          (with-temp-log-file
            (lambda (lp)
              (start-event-logging :log-file *event-log-file*)
              (issue-player-output-event 2 "Mage" "The room is dark.")
              (sleep 0.2)
              (stop-event-logging)
              (log-file-contents lp)))))
    (is (not (search "OUTPUT The room is dark." contents)))
    (is (not (search "session=2" contents)))
    (is (not (search "char=Mage" contents)))))

(test start-event-logging-no-file-is-noop
  "start-event-logging with NIL should be a no-op."
  (let ((*event-log-file* nil))
    (is (null (start-event-logging)))))

;; ---------------------------------------------------------------------------
;; handle-event generic
;; ---------------------------------------------------------------------------

(test handle-event-default-is-noop
  "The default handle-event method should return NIL for any object+event."
  (let ((obj (new-object :name "dummy")))
    (is (null (handle-event obj (make-instance 'player-input-event
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
                                                          (find-class 'player-input-event))
                                      :lambda-list '(obj ev)
                                      :function method-fn))
           (handle-event obj (make-instance 'player-input-event
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
                                            (find-class 'player-input-event))))
        (error () nil)))))
