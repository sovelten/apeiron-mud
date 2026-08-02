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

(deeds:define-event character-input-event (session-event)
  ((input :initarg :input :reader input
          :documentation "The raw input line sent by the player."))
  (:documentation "Issued whenever a player sends a line of input to the server."))

(deeds:define-event character-output-event (session-event)
  ((output :initarg :output :reader output
           :documentation "The output sent to the player's session."))
  (:documentation "Issued whenever the server sends output to a player's session."))

;; ---------------------------------------------------------------------------
;; File-logging infrastructure
;; ---------------------------------------------------------------------------

(defvar *event-log-file* nil
  "Pathname of the current event log file, or NIL if logging is disabled.")

(defun format-log-timestamp ()
  "Return a human-readable UTC timestamp string for log lines."
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour min sec)))

(defun start-event-logging (&key (log-file *event-log-file*))
  "DEPRECATED: Use CONFIGURE-LOGGING instead.

Previously opened a flat log file with Deeds-based event handlers.
Now delegates to `configure-logging` which sets up log4cl with
a size-based rolling file appender and console output.

LOG-FILE is ignored — log4cl writes to <*data-directory*>/mud.log."
  (declare (ignore log-file))
  (warn "START-EVENT-LOGGING is deprecated; use CONFIGURE-LOGGING instead.")
  (configure-logging))

(defun stop-event-logging ()
  "DEPRECATED: Use SHUTDOWN-LOGGING instead.

Previously closed the flat log file and deregistered Deeds handlers.
Now delegates to `shutdown-logging` which shuts down log4cl."
  (warn "STOP-EVENT-LOGGING is deprecated; use SHUTDOWN-LOGGING instead.")
  (shutdown-logging))

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

(defun issue-character-input-event (session-id character-name input-line)
  "Issue a character-input-event for the given session and input line."
  (deeds:do-issue character-input-event
    :session-id session-id
    :character-name character-name
    :input input-line))

(defun issue-character-output-event (session-id character-name output-text)
  "Issue a character-output-event for the given session and output text."
  (deeds:do-issue character-output-event
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

  (defmethod handle-event ((npc mud-npc) (event character-input-event))
    (when (string-equal (input event) \"hello\")
      (format t \"NPC ~A heard hello!~%\" (object-name npc))))

  ;; Register the NPC:
  (deeds:with-handler character-input-event (ev)
    (handle-event my-npc ev))
"))

(defmethod handle-event (object event)
  "Default no-op implementation.  Specialise for your game-object types."
  (declare (ignore object event))
  nil)
