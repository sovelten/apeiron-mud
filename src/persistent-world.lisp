(in-package :mud)

;; ─── Persistent wrapper classes ──────────────────────────────────────────────

(defwrapping-persistent-class persistent-object (mud-object)
  ()
  (:transient-slots properties))

(defwrapping-persistent-class persistent-room (mud-room)
  ()
  (:transient-slots properties))

(defwrapping-persistent-class persistent-guestbook (mud-guestbook)
  ()
  (:transient-slots properties entries))

(defmethod bknr.datastore:initialize-transient-instance ((gb persistent-guestbook))
  "Re-read guestbook entries from the CSV file after restore."
  (call-next-method)
  (let ((fp (guestbook-filepath gb)))
    (when fp
      (setf (guestbook-entries gb)
            (guestbook-load-from-csv (pathname fp))))))

(defwrapping-persistent-class persistent-world (mud-world)
  ())

;; ─── Persistent factory functions ───────────────────────────────────────────

(defun new-persistent-room (&key (name "A Room") (description ""))
  "Create a new persistent room stored in the BKNR datastore."
  (make-instance 'persistent-room
                 :name name
                 :description description
                 :type +object-type-room+
                 :location nil))

(defun new-persistent-guestbook (&key (name "a dusty guestbook") (filepath (namestring (merge-pathnames "guestbook.csv" *data-directory*))))
  "Create a new persistent guestbook stored in the BKNR datastore."
  (let* ((filepath-str (if (pathnamep filepath)
                           (namestring filepath)
                           filepath))
         (gb (make-instance 'persistent-guestbook
                            :name name
                            :filepath filepath-str
                            :type +object-type-item+)))
    (when filepath-str
      (mud.utils:log-message "Loading csv from ~A" filepath-str)
      (setf (guestbook-entries gb)
            (guestbook-load-from-csv (pathname filepath-str))))
    gb))

;; ─── Store lifecycle ────────────────────────────────────────────────────────

(defvar *data-directory*
  (merge-pathnames #p"data/" (asdf:system-source-directory :mud))
  "Directory for run-time data files (guestbook CSV, etc.).
   Separate from the BKNR store directory to avoid polluting snapshots.")

(defvar *store-directory*
  (merge-pathnames #p"bknr/" (asdf:system-source-directory :mud))
  "Directory for the BKNR data store.  Bound to a temp dir during tests.")

(defun open-mud-store ()
  "Open (or reopen) the BKNR data store for MUD persistence."
  (ensure-directories-exist *data-directory*)
  (when (and (boundp 'bknr.datastore:*store*)
             bknr.datastore:*store*)
    (bknr.datastore:close-store))
  (makunbound 'bknr.datastore:*store*)
  (let ((*trace-output* (make-broadcast-stream)))
    (setf bknr.datastore:*store*
          (make-instance 'bknr.datastore:mp-store
                         :directory *store-directory*
                         :subsystems (list (make-instance 'bknr.datastore:store-object-subsystem))))
    (setf *store* bknr.datastore:*store*)))

(defun sync-world ()
  "Snapshot the datastore so all persistent objects are written to disk."
  (bknr.datastore:snapshot)
  t)

;; ─── World persistence ──────────────────────────────────────────────────────

(defun initial-world ()
  "Create a fresh world with default rooms and guestbook.
   All persistent objects are created within a single transaction."
  (let ((world (make-instance 'persistent-world)))
    (bknr.datastore:with-transaction ("initial-world")
      (let ((tavern (new-persistent-room :name "The Tavern"
                              :description "There is a guestbook on top of a table. Hint: type \"write\" to write an entry on the guestbook."))
            (forest (new-persistent-room :name "A Dense Forest"))
            (guestbook (new-persistent-guestbook :name "a guestbook")))
        (room-add-object tavern guestbook)
        (room-add-exit tavern "north" forest)
        (room-add-exit forest "south" tavern)
        (world-add-object world guestbook)
        (world-add-room world tavern)
        (world-add-room world forest)
        (world-set-starting-room world tavern)))
    world))

(defun world-restore-or-initialize (&key force-new)
  "Restore the world from the BKNR datastore, or initialise a new one.
When FORCE-NEW is true any existing store data is wiped first."
  (when force-new
    (mud.utils:log-message "Forcing new world, clearing existing datastore…")
    (when (and (boundp 'bknr.datastore:*store*) bknr.datastore:*store*)
      (bknr.datastore:close-store))
    (uiop:delete-directory-tree *store-directory*
                                :validate (constantly t)
                                :if-does-not-exist :ignore)
    (makunbound 'bknr.datastore:*store*))
  (open-mud-store)
  (let ((stored-worlds (bknr.datastore:store-objects-with-class 'persistent-world)))
    (if stored-worlds
        (progn
          (setf *world* (first stored-worlds))
          (when *debug-mode*
            (mud.utils:log-message "World restored from BKNR datastore.")))
        (progn
          (setf *world* (initial-world))
          (sync-world)
          (when *debug-mode*
            (mud.utils:log-message "New world created and persisted.")))))
  *world*)

;; ─── World queries ──────────────────────────────────────────────────────────

(defun total-rooms ()
  "Return the number of persistent rooms."
  (length (bknr.datastore:store-objects-with-class 'persistent-room)))

(defun room-by-id (room-id)
  "Look up a room by its world-level ID."
  (find room-id (rooms) :key #'object-id))

(defun rooms ()
  "Return all persistent rooms."
  (bknr.datastore:store-objects-with-class 'persistent-room))

(defun starting-room ()
  "Get the starting room of the world."
  (room-by-id (get-config-key :starting-room-id)))

(defun world-new-character (character)
  "Add a character to the world, placing them in the starting room."
  (let ((room (starting-room)))
    (setf (object-location character) room)
    (room-add-object room character)
    (add-character character)))
