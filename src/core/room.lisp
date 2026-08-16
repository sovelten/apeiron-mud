(in-package #:apeiron.core)

;; Room class - a specialized mud-object

;; AREA-ROOM-CONNECTIONS is defined in area.lisp, which loads after this
;; file (AREA depends on ROOM).  Declare it up front so compiling
;; ROOM-EXIT-CONNECTIONS does not warn about the forward reference.
(declaim (ftype function area-room-connections))

(defclass mud-room (mud-object container-mixin)
  ((connections :initarg :connections
                :accessor room-connections
                :initform '()
                :documentation "List of Connection objects attached to this room
that are NOT part of an area: cross-area passages and legacy connections.
Connections inside an area live in the area itself and are found through
ROOM-AREA.")
   (area :initarg :area
         :accessor room-area
         :initform nil
         :documentation "The MUD-AREA this room belongs to, or NIL when the
room is not part of any area."))
  (:documentation "A location/room in the MUD.  A room may belong to at most
one area (see ROOM-AREA); its exits are the union of the area's connections
incident to it and its own CONNECTIONS list (see ROOM-EXIT-CONNECTIONS)."))

(defmethod object-describe ((obj mud-room))
  "Get a full description of a room including contents and exits."
  (let ((contents (container-all-objects obj))
        (exits (room-exit-list obj)))
    (format nil "~%~A~%~A~%~A~%~{~A~%~}~%~A~{~A~^, ~}~%"
            ;; Room name — bold bright white
            (bold-white (format nil "=== ~A ===" (object-name obj)))
            ;; Room description — keep default (no color)
            (object-description obj)
            ;; "You see:" header
            (bold-white "You see:")
            ;; Contents — color-coded by type
            (mapcar (lambda (obj)
                      (format nil "  - ~A" (object-describe obj)))
                    contents)
            ;; "Exits:" header
            (bold-white "Exits: ")
            ;; Exit directions — yellow, with synonyms in parens and (blocked) suffix
            (mapcar (lambda (exit-pair)
                      (let ((dir (first exit-pair))
                            (conn (second exit-pair)))
                        (let ((base (format-exit-direction dir conn obj)))
                          (if (and conn (connection-blocked-p conn))
                              (format nil "~A ~A" (yellow base) (bold-red "(blocked)"))
                              (yellow base)))))
                    exits))))

(defun new-room (&key (name "A Room") (description ""))
  "Create a new room."
  (make-instance 'mud-room
                 :name name
                 :description description
                 
                 :location nil))

(defun characters-in-room (room)
  "Return the list of MUD-CHARACTER objects currently in ROOM.

MUD-CHARACTER is defined in character.lisp, which loads after this file,
so the class is looked up at runtime via FIND-CLASS."
  (let ((character-class (find-class 'mud-character nil)))
    (when character-class
      (remove-if-not (lambda (obj) (typep obj character-class))
                     (container-all-objects room)))))

(defun room-exit-target (room direction)
  "Get the target room when moving in DIRECTION from ROOM.

Returns the room at the other end of the matching Connection, or NIL.
One-way connections only yield a target from their passable end."
  (let ((conn (connection-find room direction)))
    (when (and conn (connection-usable-p conn room))
      (connection-other-room conn room))))

(defun room-exit-connections (room)
  "Return the list of MUD-CONNECTIONs that lead out of ROOM.

When ROOM belongs to an area, the area's connections incident to ROOM are
the preferred source (they live in the area, not on the room), unioned
with the room's own CONNECTIONS list which holds cross-area and legacy
connections.  Rooms outside any area fall back to their own connections
list.  The result is deduplicated."
  (let ((area (room-area room)))
    (if area
        (remove-duplicates (append (area-room-connections area room)
                                   (room-connections room))
                           :test #'eq)
        (room-connections room))))

(defun connection-find (room direction)
  "Find a connection from ROOM in the given DIRECTION, or nil.

Searches the room's exit connections (area connections first, then the
room's own, see ROOM-EXIT-CONNECTIONS) for a connection that has
this room and direction (including direction synonyms).
Returns the connection if found."
  (find-if (lambda (c)
             (and (or (eq room (connection-room-a c))
                      (eq room (connection-room-b c)))
                  (connection-direction-matches c room direction)))
           (room-exit-connections room)))

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

(defun room-exit-list (room)
  "Return a list of (direction connection) for every usable exit in ROOM.

DIRECTION is a lowercase string, CONNECTION is the MUD-CONNECTION.
One-way connections are only listed from their passable end.  Exits come
from ROOM-EXIT-CONNECTIONS (area connections first, then the room's own)."
  (loop for conn in (room-exit-connections room)
        when (connection-usable-p conn room)
        collect (list (connection-direction-to conn room) conn)))

(defun synonyms-for-room (conn room)
  "Return the list of synonyms for CONN from ROOM's perspective.
CONN is a MUD-CONNECTION, ROOM is a MUD-ROOM.
Returns a list of strings (e.g. '(\"n\") for north), or NIL."
  (direction-synonyms (if (eq room (connection-room-a conn))
                          (connection-direction-a conn)
                          (connection-direction-b conn))))

(defun format-exit-direction (direction conn room)
  "Format an exit direction with its synonyms in parentheses.

Cardinal directions (north/south/east/west) with a matching single-letter
synonym get the compact format: (n)orth, (s)outh, (e)ast, (w)est.
Other directions with synonyms show: Direction (syn).
Directions without synonyms are shown as-is.

Examples:
  north + '(\"n\")  =>  (n)orth
  south + '(\"s\")  =>  (s)outh
  Puzzling Forest + '(\"pf\")  =>  Puzzling Forest (pf)
  north + nil        =>  north"
  (let ((synonyms (synonyms-for-room conn room)))
    (cond
      ;; Cardinal direction with first-letter synonym: (n)orth, (s)outh, etc.
      ((and synonyms
            (member direction '("north" "south" "east" "west") :test #'string=)
            (find (char direction 0) (first synonyms)
                  :test (lambda (ch syn)
                          (char-equal ch syn))))
       (format nil "(~A)~A" (subseq direction 0 1) (subseq direction 1)))
      ;; Has synonyms: Direction (syn1, syn2)
      (synonyms
       (format nil "~A (~{~A~^, ~})" direction
               (mapcar #'string-downcase synonyms)))
      ;; No synonyms: just the direction
      (t direction))))

(defun room-exit-blocked-p (room character direction)
  "Return a blocking message if the character cannot use this exit yet.

Four independent checks:
0. One-way — the connection cannot be traversed from this room
1. Regular block — the connection is blocked for everyone (locked door)
2. Challenge block — the connection requires a flag the character doesn't have (riddle)
3. Flag gate — the room requires a flag the character doesn't have (defeat NPC)"
  (let* ((dir (string-downcase direction))
         (conn (connection-find room dir)))
    (or
     ;; 0. One-way — wrong end of a one-way passage
     (when (and conn (not (connection-usable-p conn room)))
       (or (connection-one-way-message conn)
           (format nil "You can't go ~A from here." direction)))
     ;; 1. Regular block — blocked for everyone
     (connection-exit-blocked-message room dir)
     ;; 2. Challenge block — stored on the connection, per-character
     (when conn
       (let ((challenge-flag (object-get-property conn "challenge-flag")))
         (when (and challenge-flag
                    (not (object-get-property character challenge-flag)))
           (or (object-get-property conn "challenge-question")
               "A challenge blocks your way. Try: answer <your answer>"))))
     ;; 3. Flag-based gate — stored on the room
     (let ((required-flag (object-get-property room (format nil "gate-~A" dir))))
       (when (and required-flag (not (object-get-property character required-flag)))
         (or (object-get-property room (format nil "gate-~A-message" dir))
             (format nil "Something blocks the ~A exit. You are not ready to pass."
                     direction)))))))

(defun set-flag-gate (room exit-direction flag &optional message)
  "Set a flag-based gate on ROOM: the EXIT-DIRECTION is blocked until the
character has FLAG.  MESSAGE is shown when they try to pass."
  (object-set-property room (format nil "gate-~A" (string-downcase exit-direction)) flag)
  (when message
    (object-set-property room
                         (format nil "gate-~A-message" (string-downcase exit-direction))
                         message)))
