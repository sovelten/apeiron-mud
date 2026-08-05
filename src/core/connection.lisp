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
                :initform nil
                :documentation "Direction spec from ROOM-A to ROOM-B: a string
(e.g. \"north\") or a list of strings whose first element is the direction
and the rest are synonyms (e.g. '(\"north\" \"n\")).")
   (direction-b :initarg :direction-b
                :accessor connection-direction-b
                :initform nil
                :documentation "Direction spec from ROOM-B to ROOM-A: a string
(e.g. \"south\") or a list of strings whose first element is the direction
and the rest are synonyms (e.g. '(\"south\" \"s\")).")
   (blocked :initarg :blocked
            :accessor connection-blocked-p
            :initform nil
            :documentation "Whether the passage is currently blocked")
   (blocked-message :initarg :blocked-message
                    :accessor connection-blocked-message
                    :initform nil
                    :documentation "Custom message shown when blocked (e.g. a riddle)")
   (one-way :initarg :one-way
            :accessor connection-one-way
            :initform :both
            :documentation "Directionality of the passage: :BOTH (default —
passable either way), :A-TO-B (only from ROOM-A to ROOM-B), or :B-TO-A
(only from ROOM-B to ROOM-A).")
   (one-way-message :initarg :one-way-message
                    :accessor connection-one-way-message
                    :initform nil
                    :documentation "Custom message shown when a character tries to
traverse the passage the wrong way (e.g. a slope that only goes down)."))
  (:documentation "A connection between two rooms, with a direction spec at
each end (a string, or a list of strings with synonyms).  By default the
connection is bidirectional; with :ONE-WAY set to :A-TO-B or :B-TO-A it can
only be traversed in that direction.  Characters cannot traverse a blocked
connection."))

;; ─── Printing ──────────────────────────────────────────────────────────────

(defmethod print-object ((conn mud-connection) stream)
  (print-unreadable-object (conn stream :type t)
    (let ((ra (connection-room-a conn))
          (rb (connection-room-b conn)))
      (format stream "~A~@[ — ~A:~A <-> ~A:~A~]~@[ [BLOCKED]~]~@[ [ONE-WAY]~]"
              (object-name conn)
              (and ra rb (object-name ra))
              (and ra (direction-primary (connection-direction-a conn)))
              (and rb (object-name rb))
              (and rb (direction-primary (connection-direction-b conn)))
              (connection-blocked-p conn)
              (connection-one-way-p conn)))))

;; ─── Constructor ────────────────────────────────────────────────────────────

(defun make-connection (room-a direction-a room-b direction-b
                        &key (name (format nil "passage between ~A and ~A"
                                           (object-name room-a)
                                           (object-name room-b)))
                          blocked blocked-message
                          one-way one-way-message)
  "Create and return a new MUD-CONNECTION between ROOM-A and ROOM-B.

DIRECTION-A is the direction spec from ROOM-A to ROOM-B (e.g. \"north\").
DIRECTION-B is the direction spec from ROOM-B to ROOM-A (e.g. \"south\").
Each spec is a string (just the direction name) or a list of strings whose
first element is the direction and the remaining elements are synonyms
(e.g. '(\"north\" \"n\")).  Use ADD-SYNONYM to build specs.
When BLOCKED is true the passage starts blocked.
BLOCKED-MESSAGE is shown to characters when they try to pass.

ONE-WAY controls the passage's directionality:
  :BOTH    (default) passable in either direction
  :A-TO-B  passable only from ROOM-A to ROOM-B
  :B-TO-A  passable only from ROOM-B to ROOM-A
ONE-WAY-MESSAGE is shown when a character tries to traverse the passage
the wrong way (e.g. \"The slope is too steep to climb back up.\").

The connection is NOT linked into any room's connections list or world;
call CONNECT-ROOMS (in world.lisp) for that."
  (when (and one-way (not (member one-way '(:both :a-to-b :b-to-a))))
    (error "make-connection: :one-way must be :both, :a-to-b, or :b-to-a, got ~S"
           one-way))
  (make-instance 'mud-connection
                 :name name
                 :room-a room-a
                 :room-b room-b
                 :direction-a (normalize-direction direction-a)
                 :direction-b (normalize-direction direction-b)
                 :blocked blocked
                 :blocked-message blocked-message
                 :one-way (or one-way :both)
                 :one-way-message one-way-message))

(defun normalize-direction (spec)
  "Downcase a direction SPEC (string or list of strings)."
  (if (listp spec)
      (mapcar #'string-downcase spec)
      (string-downcase spec)))

(defun direction-synonyms (spec)
  "Return the synonym list from a direction SPEC (NIL for a plain string)."
  (when (listp spec)
    (rest spec)))

(defun direction-primary (spec)
  "Return the primary direction name from a direction SPEC (string or list)."
  (if (listp spec) (first spec) spec))

(defun add-synonym (direction-or-connection &rest args)
  "Add synonyms to a direction spec or to an existing connection.

With a string as the first argument it builds a direction spec:
  (add-synonym \"north\")        => \"north\"
  (add-synonym \"north\" \"n\")  => (\"north\" \"n\")

With a MUD-CONNECTION as the first argument it adds SYNONYMS to the end
of the connection whose primary direction matches DIRECTION-STRING
(case-insensitive), mutating the connection and returning it:
  (add-synonym conn \"south\" \"s\")"
  (etypecase direction-or-connection
    (string
     (if args
         (list* direction-or-connection args)
         direction-or-connection))
    (mud-connection
     (if (null args)
         (error "add-synonym: expected a direction-string to match, e.g. (add-synonym conn \"south\" \"s\")")
         (destructuring-bind (direction-string &rest synonyms) args
           (add-connection-synonyms direction-or-connection direction-string synonyms))))))

(defun add-connection-synonyms (connection direction-string synonyms)
  "Add SYNONYMS to the end of CONNECTION whose primary direction matches
DIRECTION-STRING (case-insensitive).  Mutates and returns CONNECTION."
  (when synonyms
    (cond
      ((string-equal (direction-primary (connection-direction-a connection))
                     direction-string)
       (setf (connection-direction-a connection)
             (spec-add-synonyms (connection-direction-a connection) synonyms)))
      ((string-equal (direction-primary (connection-direction-b connection))
                     direction-string)
       (setf (connection-direction-b connection)
             (spec-add-synonyms (connection-direction-b connection) synonyms)))
      (t
       (error "add-synonym: no end of ~A has direction ~S"
              (object-name connection) direction-string))))
  connection)

(defun spec-add-synonyms (spec synonyms)
  "Return SPEC with SYNONYMS appended, deduplicated (case-insensitive).
The result stays a plain string when the spec has no synonyms, otherwise
a list of strings."
  (let ((base (if (listp spec) spec (list spec))))
    (dolist (syn synonyms)
      (unless (member syn base :test #'string-equal)
        (setf base (append base (list (string-downcase syn))))))
    (if (= 1 (length base))
        (first base)
        base)))

;; ─── Helpers ────────────────────────────────────────────────────────────────

(defun connection-other-room (connection room)
  "Return the room at the other end of CONNECTION from ROOM."
  (if (eq room (connection-room-a connection))
      (connection-room-b connection)
      (connection-room-a connection)))

(defun connection-direction-to (connection room)
  "Return the primary direction name that leads out of ROOM through CONNECTION."
  (direction-primary (if (eq room (connection-room-a connection))
                         (connection-direction-a connection)
                         (connection-direction-b connection))))

;; ─── One-way passages ───────────────────────────────────────────────────────

(defun connection-one-way-p (connection)
  "Return non-NIL if CONNECTION is one-way (not passable in both directions)."
  (not (eq :both (connection-one-way connection))))

(defun connection-usable-p (connection room)
  "Return non-NIL if CONNECTION can be traversed from ROOM.

Bidirectional connections (:BOTH) are always usable.  One-way connections
are usable only from their passable end: :A-TO-B from ROOM-A, :B-TO-A from
ROOM-B."
  (ecase (connection-one-way connection)
    (:both t)
    (:a-to-b (eq room (connection-room-a connection)))
    (:b-to-a (eq room (connection-room-b connection)))))

;; ─── Blocking management ───────────────────────────────────────────────────

(defun connection-direction-matches (connection room direction)
  "Return non-NIL if DIRECTION matches the primary direction name or any
synonym for the connection end that leads out of ROOM."
  (let ((spec (if (eq room (connection-room-a connection))
                  (connection-direction-a connection)
                  (connection-direction-b connection))))
    (if (listp spec)
        (some (lambda (d) (string-equal direction d)) spec)
        (string-equal direction spec))))

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

A character who answers correctly with ANSWER sets the FLAG on themselves,
which allows them to pass.  Characters without the flag see the QUESTION
as a blocking message.  This is independent of regular connection
blocking (CONNECTION-BLOCKED-P)."
  (object-set-property connection "challenge-question" question)
  (object-set-property connection "challenge-answer" answer)
  (object-set-property connection "challenge-flag" flag))
