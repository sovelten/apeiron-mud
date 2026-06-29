;;;; src/persistence/persistent-world.lisp — BKNR datastore persistence for the MUD world

(in-package :apeiron.persistence)

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

(defwrapping-persistent-class persistent-npc (mud-npc)
  ()
  (:transient-slots properties))

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

(defun new-persistent-npc (&key name description hp max-hp attack-min attack-max
                               defeat-message victory-flag)
  "Create a new persistent NPC stored in the BKNR datastore."
  (let ((max-hp (or max-hp hp 10)))
    (make-instance 'persistent-npc
                   :name name
                   :description description
                   :type +object-type-character+
                   :hp (or hp max-hp)
                   :max-hp max-hp
                   :attack-min attack-min
                   :attack-max attack-max
                   :defeat-message defeat-message
                   :victory-flag victory-flag)))

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
      (log-message "Loading csv from ~A" filepath-str)
      (setf (guestbook-entries gb)
            (guestbook-load-from-csv (pathname filepath-str))))
    gb))

;; ─── Store lifecycle ────────────────────────────────────────────────────────

(defvar *store-directory*
  (merge-pathnames #p"bknr/" (asdf:system-source-directory :apeiron))
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

;; ─── World materialization ──────────────────────────────────────────────────

(defun clone-properties (source target)
  "Copy all properties from SOURCE to TARGET."
  (maphash (lambda (k v) (object-set-property target k v))
           (object-properties source)))

(defun materialize-object (obj persistent-world map)
  "Create a persistent copy of OBJ, register it in PERSISTENT-WORLD,
and store the mapping in MAP (transient -> persistent)."
  (let ((p (etypecase obj
               (mud-npc
                (let ((n (make-instance 'persistent-npc
                           :name (object-name obj)
                           :description (object-description obj)
                           :type (object-type obj)
                           :hp (npc-hp obj)
                           :max-hp (npc-max-hp obj)
                           :attack-min (npc-attack-min obj)
                           :attack-max (npc-attack-max obj)
                           :defeated (npc-defeated-p obj)
                           :defeat-message (npc-defeat-message obj)
                           :victory-flag (npc-victory-flag obj))))
                  (clone-properties obj n)
                  n))
               (mud-guestbook
                (let ((gb (make-instance 'persistent-guestbook
                            :name (object-name obj)
                            :description (object-description obj)
                            :type (object-type obj)
                            :filepath (guestbook-filepath obj))))
                  (clone-properties obj gb)
                  (setf (guestbook-entries gb)
                        (copy-list (guestbook-entries obj)))
                  gb))
               (mud-room
                (let ((r (make-instance 'persistent-room
                           :name (object-name obj)
                           :description (object-description obj)
                           :type (object-type obj))))
                  (clone-properties obj r)
                  r))
               (mud-object
                (let ((o (make-instance 'persistent-object
                           :name (object-name obj)
                           :description (object-description obj)
                           :type (object-type obj))))
                  (clone-properties obj o)
                  o)))))
    (world-set-object-id! persistent-world p)
    (setf (gethash obj map) p)))

(defun materialize-relationships (transient-world persistent-world map)
  "Restore cross-references between persistent objects: locations, exits,
room contents, and the starting room."
  (dolist (obj (world-all-objects transient-world))
        (unless (typep obj 'mud-character)
          (let ((p (gethash obj map)))
            (when p
              ;; Location
              (let ((old-loc (object-location obj)))
                (when old-loc
                  (let ((new-loc (gethash old-loc map)))
                    (when new-loc
                      (setf (object-location p) new-loc)))))
              ;; Room-specific relationships
              (when (typep obj 'mud-room)
                ;; Exits
                (maphash (lambda (dir target)
                           (let ((new-target (gethash target map)))
                             (when new-target
                               (room-add-exit p dir new-target))))
                         (room-exits obj))
                ;; Contents
                (loop for child across (room-contents obj)
                      do (let ((new-child (gethash child map)))
                           (when new-child
                             (room-add-object p new-child))))))))
      ;; Starting room
      (let ((old-start (starting-room transient-world)))
        (when old-start
          (let ((new-start (gethash old-start map)))
            (when new-start
              (world-set-starting-room! persistent-world new-start)))))))

(defun materialize-world (transient-world)
  "Convert a transient MUD world into a persistent one.

All rooms, objects, NPCs, and guestbooks in TRANSIENT-WORLD are re-created
as BKNR-persistent instances within a single transaction.  Relationships
(locations, exits, room contents, properties) are faithfully copied.

Returns the new PERSISTENT-WORLD."
  (let ((pw (make-instance 'persistent-world))
        (map (make-hash-table :test #'eq)))
    (bknr.datastore:with-transaction ("materialize-world")
      ;; Phase 1 — create persistent counterparts
      (dolist (obj (world-all-objects transient-world))
        (unless (typep obj 'mud-character)
          (materialize-object obj pw map)))
      ;; Phase 2 — restore cross-references
      (materialize-relationships transient-world pw map))
    pw))

;; ─── World restore / initialize ─────────────────────────────────────────────

(defun default-transient-world ()
  "Create a bare transient world with the five hub rooms and a guestbook.

Used as the fallback when WORLD-RESTORE-OR-INITIALIZE is called
without :TRANSIENT-WORLD."
  (let ((world (make-instance 'mud-world)))
    (let ((gathering (new-room :name "The Gathering"
                              :description "A warm, circular hall with a high domed ceiling. Torches flicker along the stone walls, casting dancing shadows."))
          (forest (new-room :name "A Whispering Forest"
                            :description "Ancient trees tower overhead, their leaves rustling secrets in the wind."))
          (desert (new-room :name "A Sun-Bleached Desert"
                            :description "Endless dunes of golden sand stretch to the horizon under a blinding sun."))
          (swamp (new-room :name "A Murky Swamp"
                           :description "Stagnant water laps at gnarled tree roots as thick mist curls around your ankles."))
          (volcano (new-room :name "A Rumbling Volcano"
                             :description "The ground trembles beneath your feet. Glowing lava flows through cracks in the black, jagged rock."))
          (guestbook (new-guestbook :name "an oak guestbook"
                                    :filepath (namestring (merge-pathnames "guestbook.csv" *data-directory*)))))
      (room-add-object gathering guestbook)
      (room-add-exits gathering "north" forest "south")
      (room-add-exits gathering "east" desert "west")
      (room-add-exits gathering "west" swamp "east")
      (room-add-exits gathering "south" volcano "north")
      (world-set-object-id! world guestbook)
      (world-set-object-id! world gathering)
      (world-set-object-id! world forest)
      (world-set-object-id! world desert)
      (world-set-object-id! world swamp)
      (world-set-object-id! world volcano)
      (world-set-starting-room! world gathering))
    world))

(defun world-restore-or-initialize (&key force-new (initializer #'default-transient-world))
  "Restore the world from the BKNR datastore, or materialize a fresh one.

When no stored world is found, INITIALIZER (a function of no arguments
that returns a transient MUD-WORLD) is called to produce the transient
world, which is then materialized into persistence.  Defaults to
`DEFAULT-TRANSIENT-WORLD`.

When FORCE-NEW is true any existing store data is wiped first."
  (when force-new
    (log-message "Forcing new world, clearing existing datastore…")
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
          (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-npc))
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
                (rebuild-room-contents obj))
              (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-npc))
                (rebuild-room-contents obj))))
          (when *debug-mode*
            (log-message "World restored from BKNR datastore."))
          world)
        (let* ((transient (funcall initializer))
               (world (materialize-world transient)))
          (sync-world)
          (when *debug-mode*
            (log-message "New world created from transient and persisted."))
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
