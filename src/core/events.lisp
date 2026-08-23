(in-package #:apeiron.core)

;;;;
;;;; events.lisp — Event system for the Apeiron MUD
;;;;
;;;; Built on the Deeds library, this module provides:
;;;;   1. MUD-specific event types (player input, player output, session events).
;;;;   2. Convenience functions to issue standard events.
;;;;   3. Extensibility hooks so game objects can later react to game events.
;;;;
;;;; Logging is handled by log4cl — see logging.lisp.

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

;; ── Log character inputs via log4cl ──────────────────────────────────────

(deeds:define-handler (log-character-input character-input-event)
    (ev input session-id character-name)
  (log:info "INPUT ~A [session=~A char=~A]" input session-id character-name))

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
