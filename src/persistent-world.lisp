(in-package :mud)

;; ─── Persistent wrapper classes ──────────────────────────────────────────────

(defwrapping-persistent-class persistent-object (mud-object)
  ()
  (:transient-slots properties))

(defwrapping-persistent-class persistent-room (mud-room)
  ()
  (:transient-slots properties contents))

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
  ()
  (:transient-slots players objects rooms))

;; ─── Persistent factory functions ───────────────────────────────────────────

(defun new-persistent-object (&key (name "An Object") (description ""))
  "Create a new persistent object stored in the BKNR datastore."
  (make-instance 'persistent-object
                 :name name
                 :description description
                 :type +object-type-room+
                 :location nil))

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
  "Open the BKNR data store for MUD persistence.
If the store is already open it is reused to avoid unnecessary
close/reopen cycles that trigger BKNR transaction log replay warnings."
  (ensure-directories-exist *data-directory*)
  (unless (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
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
      (let ((gathering (new-persistent-room :name "The Gathering"
                                            :description "A warm, circular hall with a high domed ceiling. Torches flicker along the stone walls, casting dancing shadows. Four archways stand at the cardinal points, each bearing a carved symbol: a leaf (north), a sun (east), a droplet (west), and a flame (south). A sturdy oak guestbook sits on a pedestal in the centre."))
            (forest (new-persistent-room :name "A Whispering Forest"
                                         :description "Ancient trees tower overhead, their leaves rustling secrets in the wind. Shafts of golden sunlight pierce the canopy, illuminating patches of moss and wildflowers. A faint path winds deeper into the woods."))
            (desert (new-persistent-room :name "A Sun-Bleached Desert"
                                         :description "Endless dunes of golden sand stretch to the horizon under a blinding sun. The heat shimmers in waves, and the silence is broken only by the occasional skitter of a unseen creature. The bleached bones of a long-dead beast protrude from a nearby dune."))
            (swamp (new-persistent-room :name "A Murky Swamp"
                                        :description "Stagnant water laps at gnarled tree roots as thick mist curls around your ankles. The air is heavy with the smell of decay and damp earth. Somewhere in the distance, a bullfrog croaks and something large splashes."))
            (volcano (new-persistent-room :name "A Rumbling Volcano"
                                          :description "The ground trembles beneath your feet. Glowing lava flows through cracks in the black, jagged rock, casting an eerie red glow across the cavern. Heat shimmers violently and the air reeks of sulphur. The mountain groans above you."))
            (guestbook (new-persistent-guestbook :name "an oak guestbook")))
        ;; Place the guestbook in The Gathering
        (room-add-object gathering guestbook)
        ;; Connect The Gathering (hub) to the four biomes
        (room-add-exits gathering "north" forest "south")
        (room-add-exits gathering "east" desert "west")
        (room-add-exits gathering "west" swamp "east")
        (room-add-exits gathering "south" volcano "north")
        ;; Register all objects in the world
        (world-set-object-id! world guestbook)
        (world-set-object-id! world gathering)
        (world-set-object-id! world forest)
        (world-set-object-id! world desert)
        (world-set-object-id! world swamp)
        (world-set-object-id! world volcano)
        (world-set-starting-room! world gathering)))
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
        (let ((world (first stored-worlds)))
          ;; Populate world's indices from BKNR objects
          (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-object))
            (world-set-object-id! world obj))
          (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-room))
            (world-set-object-id! world obj))
          (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-guestbook))
            (world-set-object-id! world obj))
          ;; Reset room contents (transient) before rebuilding from persistent
          ;; object locations, so transient objects from previous sessions
          ;; (e.g. characters added in earlier tests) don't accumulate.
          (dolist (r (bknr.datastore:store-objects-with-class 'persistent-room))
            (setf (room-contents r) (make-array 0 :adjustable t :fill-pointer t)))
          ;; Rebuild room contents from persistent object locations.
          ;; Wrapped in a single transaction to avoid per-object auto-wrap overhead.
          (bknr.datastore:with-transaction ("rebuild-room-contents")
            (flet ((rebuild-room-contents (obj)
                     (let ((loc (object-location obj)))
                       (when (typep loc 'persistent-room)
                         (room-add-object loc obj)))))
              (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-object))
                (rebuild-room-contents obj))
              (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-room))
                (rebuild-room-contents obj))
              (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-guestbook))
                (rebuild-room-contents obj))))
          (when *debug-mode*
            (mud.utils:log-message "World restored from BKNR datastore."))
          world)
        (let ((world (initial-world)))
          (sync-world)
          (when *debug-mode*
            (mud.utils:log-message "New world created and persisted."))
          world))))

;; ─── World queries ──────────────────────────────────────────────────────────

(defun get-persistent-world ()
  (let ((worlds (bknr.datastore:store-objects-with-class 'persistent-world)))
    (when worlds
      (first worlds))))

(defun total-rooms ()
  "Return the number of persistent rooms.
Note: Prefer (world-total-rooms world) in new code."
  (length (bknr.datastore:store-objects-with-class 'persistent-room)))

(defun room-by-id (room-id)
  "Look up a persistent room by its world-level ID.
Note: Prefer (world-room-by-id world room-id) in new code."
  (find room-id (rooms) :key #'object-id))

(defun rooms ()
  "Return all persistent rooms.
Note: Prefer (world-rooms world) in new code."
  (bknr.datastore:store-objects-with-class 'persistent-room))
