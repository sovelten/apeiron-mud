;;;; src/persistence/persistent-world.lisp — BKNR datastore persistence for the MUD world

(in-package :apeiron.persistence)

;; ─── Persistent wrapper classes ──────────────────────────────────────────────

(defwrapping-persistent-class persistent-object (mud-object)
  ()
  (:transient-slots properties))

(defwrapping-persistent-class persistent-room (mud-room persistent-object)
  ()
  (:transient-slots contents))

(defwrapping-persistent-class persistent-guestbook (mud-guestbook persistent-object)
  ()
  (:transient-slots entries))

(defwrapping-persistent-class persistent-npc (mud-npc persistent-object)
  ())

(defwrapping-persistent-class persistent-connection (mud-connection persistent-object)
  ())

(defmethod bknr.datastore:initialize-transient-instance ((gb persistent-guestbook))
  "Re-read guestbook entries from the CSV file after restore."
  (call-next-method)
  (let ((fp (guestbook-filepath gb)))
    (when fp
      (setf (guestbook-entries gb)
            (guestbook-load-from-csv (pathname fp))))))

(defmethod bknr.datastore:initialize-transient-instance ((conn persistent-connection))
  "Re-register the connection in each room's connections list after restore."
  (call-next-method)
  (let ((room-a (connection-room-a conn))
        (room-b (connection-room-b conn)))
    (when (and room-a room-b)
      (push conn (room-connections room-a))
      (push conn (room-connections room-b)))))

(defwrapping-persistent-class persistent-world (mud-world)
  ()
  (:transient-slots players objects rooms))

(defmethod create-object! ((world persistent-world) object)
  "Register OBJECT in WORLD by materializing a persistent copy."
  (bknr.datastore:with-transaction ("create-object")
    (materialize-object object world)))

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
    ))

(defun sync-world ()
  "Snapshot the datastore so all persistent objects are written to disk."
  (bknr.datastore:snapshot)
  t)

;; ─── World materialization ──────────────────────────────────────────────────

(defun clone-properties (source target)
  "Copy all properties from SOURCE to TARGET."
  (maphash (lambda (k v) (object-set-property target k v))
           (object-properties source)))

(defun materialize-object (obj persistent-world)
  "Create a persistent copy of OBJ and register it in PERSISTENT-WORLD."
  (let ((p (etypecase obj
               (mud-npc
                (let ((n (make-instance 'persistent-npc
                           :name (object-name obj)
                           :description (object-description obj)
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
                            :filepath (guestbook-filepath obj))))
                  (clone-properties obj gb)
                  (setf (guestbook-entries gb)
                        (copy-list (guestbook-entries obj)))
                  gb))
               (mud-room
                (let ((r (make-instance 'persistent-room
                           :name (object-name obj)
                           :description (object-description obj))))
                  (clone-properties obj r)
                  r))
               (mud-connection
                (let ((c (make-instance 'persistent-connection
                            :name (object-name obj)
                            :description (object-description obj)
                            :direction-a (connection-direction-a obj)
                            :direction-b (connection-direction-b obj)
                            :blocked (connection-blocked-p obj)
                            :blocked-message (connection-blocked-message obj))))
                  (clone-properties obj c)
                  c))
               (mud-object
                (let ((o (make-instance 'persistent-object
                           :name (object-name obj)
                           :description (object-description obj))))
                  (clone-properties obj o)
                  o)))))
    ;; Use same ID as the transient original so persistent counterparts
    ;; can be found via WORLD-OBJECT-BY-ID / WORLD-OBJECTS during restoration.
    (setf (object-id p) (object-id obj))
    (world-add-object! persistent-world p)))

(defun materialize-relationships (transient-world persistent-world)
  "Restore cross-references between persistent objects: locations, exits,
room contents, and the starting room.  Persistent counterparts are found
by matching IDs in PERSISTENT-WORLD's object index."
  (dolist (obj (world-all-objects transient-world))
        (unless (typep obj 'mud-character)
          (let ((p (world-object-by-id persistent-world (object-id obj))))
            (when p
              ;; Location
              (let ((old-loc (object-location obj)))
                (when old-loc
                  (let ((new-loc (world-object-by-id persistent-world (object-id old-loc))))
                    (when new-loc
                      (setf (object-location p) new-loc)))))
              ;; Connection room references
              (when (typep obj 'mud-connection)
                (let ((room-a (world-object-by-id persistent-world
                                                  (object-id (connection-room-a obj))))
                      (room-b (world-object-by-id persistent-world
                                                  (object-id (connection-room-b obj)))))
                  (when (and room-a room-b)
                    (setf (connection-room-a p) room-a
                          (connection-room-b p) room-b)
                    ;; Re-register in each room's connections list
                    (push p (room-connections room-a))
                    (push p (room-connections room-b)))))
              ;; Room-specific relationships
              (when (typep obj 'mud-room)
                ;; Contents
                (loop for child in (container-all-objects obj)
                      do (let ((new-child (world-object-by-id persistent-world (object-id child))))
                           (when new-child
                             (container-add-object p new-child))))))))
      ;; Starting room
      (let ((old-start (starting-room transient-world)))
        (when old-start
          (let ((new-start (world-object-by-id persistent-world (object-id old-start))))
            (when new-start
              (world-set-starting-room! persistent-world new-start)))))))

(defun materialize-world (transient-world)
  "Convert a transient MUD world into a persistent one.

All rooms, objects, NPCs, and guestbooks in TRANSIENT-WORLD are re-created
as BKNR-persistent instances within a single transaction.  Relationships
(locations, exits, room contents, properties) are faithfully copied.

Returns the new PERSISTENT-WORLD."
  (let ((pw (make-instance 'persistent-world)))
    (bknr.datastore:with-transaction ("materialize-world")
      ;; Phase 1 — create persistent counterparts
      (dolist (obj (world-all-objects transient-world))
        (unless (typep obj 'mud-character)
          (materialize-object obj pw)))
      ;; Phase 2 — restore cross-references
      (materialize-relationships transient-world pw))
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
          (guestbook (new-guestbook :name "an oak guestbook")))
      (container-add-object gathering guestbook)
      (connect-rooms world gathering "north" forest "south")
      (connect-rooms world gathering "east" desert "west")
      (connect-rooms world gathering "west" swamp "east")
      (connect-rooms world gathering "south" volcano "north")
      (world-add-object! world guestbook)
      (world-add-object! world gathering)
      (world-add-object! world forest)
      (world-add-object! world desert)
      (world-add-object! world swamp)
      (world-add-object! world volcano)
      (world-set-starting-room! world gathering))
    world))

(defun get-persistent-world ()
  "Return world instance persisted in bknr store"
  (let ((worlds (bknr.datastore:store-objects-with-class 'persistent-world)))
    (when worlds
      (first worlds))))

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
  (let ((world (get-persistent-world)))
    (if world
        (progn
          ;; Populate world's indices from BKNR objects.
          ;; persistent-object queries also return subclasses (room, guestbook, npc).
          (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-object))
            (world-add-object! world obj))
          ;; Rebuild room contents from persistent object locations.
          ;; persistent-object queries also return subclasses (room, guestbook, npc).
          ;; Wrapped in a single transaction to avoid per-object auto-wrap overhead.
          (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-object))
            (let ((location (object-location obj)))
              (when (typep location 'persistent-room)
                (container-add-object location obj))))
          (when *debug-mode*
            (log-message "World restored from BKNR datastore."))
          world)
        (let* ((transient (funcall initializer))
               (world (materialize-world transient)))
          (sync-world)
          (when *debug-mode*
            (log-message "New world created from transient and persisted."))
          world))))
