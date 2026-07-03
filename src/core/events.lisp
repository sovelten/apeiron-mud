(in-package #:apeiron.core)

;;;;
;;;; events.lisp — Event system for the Apeiron MUD
;;;;
;;;; Built on the Deeds library, this module provides:
;;;;   1. MUD-specific event types (player input, player output, session events).
;;;;   2. File-logging infrastructure that writes all output (info, error) and
;;;;      player input to a log file for debugging.
;;;;   3. Extensibility hooks so game objects can later react to game events.
;;;;
;;;; The machinery is designed so that the same event loop can be reused
;;;; when richer game-event handling (combat notifications, room changes,
;;;; quest progress, etc.) is layered on top.

;; ---------------------------------------------------------------------------
;; MUD-specific event types
;; ---------------------------------------------------------------------------

;; Base for all Apeiron events — currently we piggyback on deeds:event
;; directly, but defining our own subclass allows future common behaviour.

(deeds:define-event mud-event ()
  ()
  (:documentation "Base class for all Apeiron MUD events.

Events that represent something that happened in the MUD world should
inherit from this class rather than deeds:event directly, so that handlers
can select for all MUD events with a single event-type specifier."))

(deeds:define-event session-event (mud-event)
  ((session-id :initarg :session-id :reader session-id
               :documentation "Unique identifier of the session that triggered the event.")
   (character-name :initarg :character-name :reader character-name
                   :documentation "Name of the character (or NIL if not yet set)."))
  (:documentation "Base class for events tied to a particular player session."))

(deeds:define-event player-input-event (session-event)
  ((input :initarg :input :reader input
          :documentation "The raw input line sent by the player."))
  (:documentation "Issued whenever a player sends a line of input to the server."))

(deeds:define-event player-output-event (session-event)
  ((output :initarg :output :reader output
           :documentation "The output sent to the player's session."))
  (:documentation "Issued whenever the server sends output to a player's session."))

;; ---------------------------------------------------------------------------
;; File-logging infrastructure
;; ---------------------------------------------------------------------------

(defvar *event-log-file* nil
  "Pathname of the current event log file, or NIL if logging is disabled.")

(defvar *event-log-stream* nil
  "The output stream for the event log file.
Only meaningful inside the log-writer lock; do not read directly.")

(defvar *event-log-lock* (bordeaux-threads:make-lock "event-log-lock")
  "Mutex that serialises writes to the event log file.")

(defvar *event-log-handlers* nil
  "List of handler instances registered for file logging.
Used during shutdown to deregister them.")

(defun format-log-timestamp ()
  "Return a human-readable UTC timestamp string for log lines."
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour min sec)))

(defun %write-log-line (level message &key session-id character-name)
  "Write a single formatted line to the event log file.
LEVEL is a keyword like :INFO, :ERROR, :WARN, :INPUT, or :OUTPUT.
Called from within the delivery-function of the logging handlers."
  (bordeaux-threads:with-lock-held (*event-log-lock*)
    (when *event-log-stream*
      (format *event-log-stream* "[~A] ~A ~A~@[ [session=~A]~]~@[ [char=~A]~]~%"
              (format-log-timestamp)
              level
              message
              session-id
              character-name)
      (force-output *event-log-stream*))))

(defun start-event-logging (&key (log-file *event-log-file*))
  "Start writing events to a log file.

LOG-FILE is the pathname of the log file.  If not supplied, uses the
current value of *EVENT-LOG-FILE*.  When LOG-FILE is NIL, logging is
not started.

Registers queued-handler instances on the standard Deeds event loop that
write formatted log lines for info/error/warning/player-input/player-output
events.  Returns T if logging was started, NIL otherwise."
  (when log-file
    ;; Close any previously open log.
    (stop-event-logging)
    (setf *event-log-file* log-file)
    (ensure-directories-exist log-file)
    (setf *event-log-stream* (open log-file
                                   :direction :output
                                   :if-exists :append
                                   :if-does-not-exist :create))
    (%write-log-line :SYSTEM "=== Event logging started ===")
    ;; Register one handler per event type so we can format each correctly.
    (push (deeds:with-handler deeds:info-event (ev message)
            (%write-log-line :INFO message))
          *event-log-handlers*)
    (push (deeds:with-handler deeds:error-event (ev message)
            (%write-log-line :ERROR message))
          *event-log-handlers*)
    (push (deeds:with-handler deeds:warning-event (ev message)
            (%write-log-line :WARN message))
          *event-log-handlers*)
    (push (deeds:with-handler player-input-event (ev input session-id character-name)
            (%write-log-line :INPUT input
                             :session-id session-id
                             :character-name character-name))
          *event-log-handlers*)
    (push (deeds:with-handler player-output-event (ev output session-id character-name)
            (%write-log-line :OUTPUT output
                             :session-id session-id
                             :character-name character-name))
          *event-log-handlers*)
    t))

(defun stop-event-logging ()
  "Stop event logging and close the log file.
Deregisters all file-logging handlers from the event loop."
  (when *event-log-stream*
    (%write-log-line :SYSTEM "=== Event logging stopped ===")
    (dolist (handler *event-log-handlers*)
      (ignore-errors
       (deeds:deregister-handler handler deeds:*standard-event-loop*)
       (deeds:stop handler)))
    (setf *event-log-handlers* nil)
    (close *event-log-stream*)
    (setf *event-log-stream* nil
          *event-log-file* nil))
  (values))

;; ---------------------------------------------------------------------------
;; Convenience: issue standard events
;; ---------------------------------------------------------------------------

(defun issue-info-event (format-string &rest format-args)
  "Issue an informational message as a Deeds info-event."
  (deeds:do-issue deeds:info-event
    :message (apply #'format nil format-string format-args)))

(defun issue-error-event (format-string &rest format-args)
  "Issue an error message as a Deeds error-event."
  (deeds:do-issue deeds:error-event
    :message (apply #'format nil format-string format-args)))

(defun issue-warning-event (format-string &rest format-args)
  "Issue a warning message as a Deeds warning-event."
  (deeds:do-issue deeds:warning-event
    :message (apply #'format nil format-string format-args)))

(defun issue-player-input-event (session-id character-name input-line)
  "Issue a player-input-event for the given session and input line."
  (deeds:do-issue player-input-event
    :session-id session-id
    :character-name character-name
    :input input-line))

(defun issue-player-output-event (session-id character-name output-text)
  "Issue a player-output-event for the given session and output text."
  (deeds:do-issue player-output-event
    :session-id session-id
    :character-name character-name
    :output output-text))

;; ---------------------------------------------------------------------------
;; Extensibility: generic handle-event for game objects
;; ---------------------------------------------------------------------------

(defgeneric handle-event (object event)
  (:documentation "Called on OBJECT when an EVENT is issued.

Game objects (NPCs, rooms, items, etc.) can specialise this generic function
to react to events they care about.  The default implementation is a no-op.

To receive events, an object must also register itself as a handler on the
event loop via DEEDS:REGISTER-HANDLER (or the higher-level helpers above).

Example:

  (defmethod handle-event ((npc mud-npc) (event player-input-event))
    (when (string-equal (input event) \"hello\")
      (format t \"NPC ~A heard hello!~%\" (object-name npc))))

  ;; Register the NPC:
  (deeds:with-handler player-input-event (ev)
    (handle-event my-npc ev))
"))

(defmethod handle-event (object event)
  "Default no-op implementation.  Specialise for your game-object types."
  (declare (ignore object event))
  nil)
