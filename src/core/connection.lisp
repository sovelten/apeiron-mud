;;;; src/core/connection.lisp — Reified connections between rooms
;;;;
;;;; A Connection is a first-class MUD object representing a bidirectional
;;;; passage between two rooms.  ROOM-GET-EXIT falls back to CONNECTION-FIND
;;;; so connections work transparently alongside legacy string-based exits.

(in-package #:apeiron.core)

(defclass mud-connection (mud-object)
  ((room-a :initarg :room-a
           :accessor connection-room-a
           :initform nil
           :documentation "First room in the connection")
   (room-b :initarg :room-b
           :accessor connection-room-b
           :initform nil
           :documentation "Second room in the connection")
   (direction-a :initarg :direction-a
                :accessor connection-direction-a
                :documentation "Direction name from ROOM-A to ROOM-B (e.g. \"north\")")
   (direction-b :initarg :direction-b
                :accessor connection-direction-b
                :documentation "Direction name from ROOM-B to ROOM-A (e.g. \"south\")")
   (synonyms-a :initarg :synonyms-a
               :accessor connection-synonyms-a
               :initform nil
               :documentation "List of alternative direction names from ROOM-A to ROOM-B (e.g. (\"n\"))")
   (synonyms-b :initarg :synonyms-b
               :accessor connection-synonyms-b
               :initform nil
               :documentation "List of alternative direction names from ROOM-B to ROOM-A (e.g. (\"s\"))")
   (blocked :initarg :blocked
            :accessor connection-blocked-p
            :initform nil
            :documentation "Whether the passage is currently blocked")
   (blocked-message :initarg :blocked-message
                    :accessor connection-blocked-message
                    :initform nil
                    :documentation "Custom message shown when blocked (e.g. a riddle)"))
  (:documentation "A bidirectional connection between two rooms, with a direction
name at each end.  Characters cannot traverse a blocked connection."))

;; ─── Printing ──────────────────────────────────────────────────────────────

(defmethod print-object ((conn mud-connection) stream)
  (print-unreadable-object (conn stream :type t)
    (let ((ra (connection-room-a conn))
          (rb (connection-room-b conn)))
      (format stream "~A~@[ — ~A:~A <-> ~A:~A~]~@[ [BLOCKED]~]"
              (object-name conn)
              (and ra rb (object-name ra))
              (and ra (connection-direction-a conn))
              (and rb (object-name rb))
              (and rb (connection-direction-b conn))
              (connection-blocked-p conn)))))

;; ─── Constructor ────────────────────────────────────────────────────────────

(defun make-connection (room-a direction-a room-b direction-b
                        &key (name (format nil "passage between ~A and ~A"
                                           (object-name room-a)
                                           (object-name room-b)))
                          blocked blocked-message
                          synonyms-a synonyms-b)
  "Create and return a new MUD-CONNECTION between ROOM-A and ROOM-B.

DIRECTION-A is the direction name from ROOM-A to ROOM-B (e.g. \"north\").
DIRECTION-B is the direction name from ROOM-B to ROOM-A (e.g. \"south\").
SYNONYMS-A and SYNONYMS-B are lists of alternative names for each direction
(e.g. '(\"n\") for \"north\").
When BLOCKED is true the passage starts blocked.
BLOCKED-MESSAGE is shown to players when they try to pass.

The connection is NOT linked into any room's connections list or world;
call CONNECT-ROOMS (in world.lisp) for that."
  (make-instance 'mud-connection
                 :name name
                 :room-a room-a
                 :room-b room-b
                 :direction-a (string-downcase direction-a)
                 :direction-b (string-downcase direction-b)
                 :synonyms-a (mapcar #'string-downcase synonyms-a)
                 :synonyms-b (mapcar #'string-downcase synonyms-b)
                 :blocked blocked
                 :blocked-message blocked-message))

;; ─── Helpers ────────────────────────────────────────────────────────────────

(defun connection-other-room (connection room)
  "Return the room at the other end of CONNECTION from ROOM."
  (if (eq room (connection-room-a connection))
      (connection-room-b connection)
      (connection-room-a connection)))

(defun connection-direction-to (connection room)
  "Return the direction name that leads out of ROOM through CONNECTION."
  (if (eq room (connection-room-a connection))
      (connection-direction-a connection)
      (connection-direction-b connection)))

;; ─── Blocking management ───────────────────────────────────────────────────

(defun connection-direction-matches (connection room direction)
  "Return non-NIL if DIRECTION matches the primary direction name or any
synonym for the connection end that leads out of ROOM."
  (or (string-equal direction (connection-direction-to connection room))
      (let ((synonyms (if (eq room (connection-room-a connection))
                          (connection-synonyms-a connection)
                          (connection-synonyms-b connection))))
        (some (lambda (syn) (string-equal direction syn)) synonyms))))

(defun connection-find (room direction)
  "Find a connection from ROOM in the given DIRECTION, or nil.

Searches the room's connections list for a connection that has
this room and direction (including direction synonyms).
Returns the connection if found."
  (find-if (lambda (c)
             (and (or (eq room (connection-room-a c))
                      (eq room (connection-room-b c)))
                  (connection-direction-matches c room direction)))
           (room-connections room)))

(defun connection-exit-blocked-message (room direction)
  "Return a blocking message if a connection in this direction is blocked, or nil.

When the connection has a custom BLOCKED-MESSAGE (e.g. a riddle question)
that is returned; otherwise a generic \"X is blocked\" message is used."
  (let ((conn (connection-find room direction)))
    (when (and conn (connection-blocked-p conn))
      (or (connection-blocked-message conn)
          (format nil "~A is blocked. You cannot go ~A."
                  (object-name conn)
                  direction)))))

(defun connection-set-challenge (connection question answer flag)
  "Set a challenge (riddle/password) on a CONNECTION.

A player who answers correctly with ANSWER sets the FLAG on themselves,
which allows them to pass.  Players without the flag see the QUESTION
as a blocking message.  This is independent of regular connection
blocking (CONNECTION-BLOCKED-P)."
  (object-set-property connection "challenge-question" question)
  (object-set-property connection "challenge-answer" answer)
  (object-set-property connection "challenge-flag" flag))
