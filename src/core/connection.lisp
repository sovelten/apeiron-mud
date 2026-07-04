;;;; src/core/connection.lisp — Reified connections between rooms
;;;;
;;;; A Connection is a first-class MUD object representing a bidirectional
;;;; passage between two rooms.  It lives alongside the legacy string-based
;;;; exit system: ROOM-GET-EXIT falls back to CONNECTION-FIND when no
;;;; hash-table entry exists, so connections work transparently.

(in-package #:apeiron.core)

(defclass mud-connection (mud-object)
  ((room-a :initarg :room-a
           :accessor connection-room-a
           :documentation "First room in the connection")
   (room-b :initarg :room-b
           :accessor connection-room-b
           :documentation "Second room in the connection")
   (direction-a :initarg :direction-a
                :accessor connection-direction-a
                :documentation "Direction name from ROOM-A to ROOM-B (e.g. \"north\")")
   (direction-b :initarg :direction-b
                :accessor connection-direction-b
                :documentation "Direction name from ROOM-B to ROOM-A (e.g. \"south\")")
   (blocked :initarg :blocked
            :accessor connection-blocked-p
            :initform nil
            :documentation "Whether the passage is currently blocked"))
  (:documentation "A bidirectional connection between two rooms, with a direction
name at each end.  Characters cannot traverse a blocked connection."))

;; ─── Printing ──────────────────────────────────────────────────────────────

(defmethod print-object ((conn mud-connection) stream)
  (print-unreadable-object (conn stream :type t)
    (format stream "~A — ~A:~A <-> ~A:~A~@[ [BLOCKED]~]"
            (object-name conn)
            (object-name (connection-room-a conn))
            (connection-direction-a conn)
            (object-name (connection-room-b conn))
            (connection-direction-b conn)
            (connection-blocked-p conn))))

;; ─── Constructor ────────────────────────────────────────────────────────────

(defun connect-rooms (room-a direction-a room-b direction-b
                      &key (name (format nil "passage between ~A and ~A"
                                         (object-name room-a)
                                         (object-name room-b)))
                        blocked)
  "Create a bidirectional Connection between ROOM-A and ROOM-B.

DIRECTION-A is the direction name from ROOM-A to ROOM-B (e.g. \"north\").
DIRECTION-B is the direction name from ROOM-B to ROOM-A (e.g. \"south\").
When BLOCKED is true the passage starts blocked and cannot be traversed.

The connection is recorded in each room's CONNECTIONS list.  Lookup
happens via ROOM-GET-EXIT which falls back to CONNECTION-FIND when no
hash-table entry exists.

Returns the new MUD-CONNECTION instance."
  (let ((conn (make-instance 'mud-connection
                             :name name
                             :room-a room-a
                             :room-b room-b
                             :direction-a (string-downcase direction-a)
                             :direction-b (string-downcase direction-b)
                             :blocked blocked)))
    ;; Record the connection on both rooms
    (push conn (room-connections room-a))
    (push conn (room-connections room-b))
    conn))

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

(defun connection-find (room direction)
  "Find a connection from ROOM in the given DIRECTION, or nil.

Searches the room's connections list for a connection that has
this room and direction.  Returns the connection if found."
  (find-if (lambda (c)
             (and (or (eq room (connection-room-a c))
                      (eq room (connection-room-b c)))
                  (string-equal direction
                                (connection-direction-to c room))))
           (room-connections room)))

(defun connection-exit-blocked-message (room direction)
  "Return a blocking message if a connection in this direction is blocked, or nil.

Checks whether a Connection on ROOM in DIRECTION exists and is blocked.
Returns the connection's name as part of the message so the player knows
why they can't pass."
  (let ((conn (connection-find room direction)))
    (when (and conn (connection-blocked-p conn))
      (format nil "~A is blocked. You cannot go ~A."
              (object-name conn)
              direction))))
