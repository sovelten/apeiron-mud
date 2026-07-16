;;;; src/persistence/persistent-world.lisp — BKNR datastore persistence for the MUD world

(in-package :apeiron.persistence)

;; ─── Persistent wrapper classes ──────────────────────────────────────────────

(defwrapping-persistent-class persistent-object (mud-object)
  ()
  ;; properties is intentionally NOT transient — objects store meaningful
  ;; game state via object-set-property that must survive restarts.
  (:transient-slots))

(defwrapping-persistent-class persistent-room (mud-room persistent-object)
  ()
  (:transient-slots contents))

(defwrapping-persistent-class persistent-guestbook (mud-guestbook persistent-object)
  ()
  (:transient-slots entries))

(defwrapping-persistent-class persistent-npc (mud-npc persistent-object)
  ())

(defwrapping-persistent-class persistent-wordle (mud-wordle-puzzle persistent-object)
  ()
  (:transient-slots player-guesses))

(defwrapping-persistent-class persistent-connection (mud-connection persistent-object)
  ())

(defmethod bknr.datastore:initialize-transient-instance ((gb persistent-guestbook))
  "Re-read guestbook entries from the CSV file after restore."
  (call-next-method)
  (let ((fp (guestbook-filepath gb)))
    (when fp
      (setf (guestbook-entries gb)
            (guestbook-load-from-csv (pathname fp))))))

(defun refresh-guestbooks ()
  "Reload all guestbook entries from their CSV files.
Run this after restarting the server if guestbook entries look stale.
Usage from the MUD: eval (refresh-guestbooks)"
  (dolist (gb (bknr.datastore:store-objects-with-class 'persistent-guestbook))
    (let ((fp (guestbook-filepath gb)))
      (when fp
        (setf (guestbook-entries gb)
              (guestbook-load-from-csv (pathname fp))))
      (log-message "Refreshed guestbook ~A from ~A" (object-name gb) fp)))
  (values))

(defwrapping-persistent-class persistent-world (mud-world)
  ()
  (:transient-slots players objects rooms))

(defmethod object-set-property ((obj persistent-object) property-name value)
  "Set a property on a persistent object, ensuring BKNR tracks the change.

The default method modifies the hash-table in-place, which is invisible
to BKNR.  This method additionally writes the hash-table reference back
to the slot.  The write triggers wrapping-persistent-class's auto-wrap
(which creates a transaction when needed) and BKNR's (setf
slot-value-using-class) :after method, which encodes
tx-change-slot-values into the transaction log.

When called from within an existing transaction (e.g. during
materialize-object), the auto-wrap passes through and BKNR records the
change in the outer transaction's buffer."
  (setf (gethash property-name (object-properties obj)) value)
  ;; Write the slot so BKNR records the change — see docstring above.
  (setf (object-properties obj) (object-properties obj)))

(defmethod create-object! ((world persistent-world) object)
  "Register OBJECT in WORLD by converting it to a persistent object in-place.
The transient OBJECT is converted in-place via MATERIALIZE-OBJECT, which
uses CHANGE-CLASS to preserve slot values and object identity."
  (bknr.datastore:with-transaction ("create-object")
    (materialize-object object)
    (world-add-object! world object))
  object)

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
    ;; Ensure the APEIRON.EVAL package exists before BKNR reads snapshot
    ;; data.  The /eval command creates symbols in this package at runtime,
    ;; and those may be persisted in the snapshot.  If the package doesn't
    ;; exist when BKNR tries to restore them, we get a
    ;; FIND-SYMBOL-INTERACTIVELY error.
    (apeiron.core::eval-context-package)
    (setf bknr.datastore:*store*
          (make-instance 'bknr.datastore:mp-store
                         :directory *store-directory*
                         :subsystems (list (make-instance 'bknr.datastore:store-object-subsystem))))))

(defun sync-world ()
  "Snapshot the datastore so all persistent objects are written to disk."
  (bknr.datastore:snapshot)
  t)

;; ─── Persistent class mapping ───────────────────────────────────────────────

(defvar *transient->persistent-class-map*
  (make-hash-table :test #'eq)
  "Maps a transient game-object class to its wrapping persistent class.")

(defun build-persistent-class-map ()
  "Auto-discover the transient→persistent class mapping.

Walks all direct subclasses of STORE-OBJECT.  For each with
WRAPPING-PERSISTENT-CLASS as metaclass, finds the non-store-object
parent (the transient game class) and records the mapping."
  (clrhash *transient->persistent-class-map*)
  (dolist (subclass (sb-mop:class-direct-subclasses
                     (find-class 'bknr.datastore:store-object)))
    (when (typep subclass 'wrapping-persistent-class)
      (dolist (super (sb-mop:class-direct-superclasses subclass))
        (when (and (typep super 'sb-mop:standard-class)
                   (not (subtypep super 'bknr.datastore:store-object)))
          (setf (gethash super *transient->persistent-class-map*) subclass))))))

(defun transient->persistent-class (transient-class)
  "Return the persistent class that wraps TRANSIENT-CLASS."
  (or (gethash transient-class *transient->persistent-class-map*)
      (error "No persistent class found for ~A -- did you forget a DEFWRAPPING-PERSISTENT-CLASS?"
             transient-class)))

;; ─── World materialization ──────────────────────────────────────────────────

(defgeneric materialize-object (obj)
  (:documentation
   "Convert OBJ into its persistent counterpart and register it with BKNR.

Dispatching on the class of OBJ allows adding new object types without
modifying this generic function -- just add a DEFWRAPPING-PERSISTENT-CLASS
and optionally specialize MATERIALIZE-OBJECT if extra steps are needed.

Uses CHANGE-CLASS (preserving object identity and all cross-references)
followed by INITIALIZE-INSTANCE to trigger BKNR registration."))

(defmethod materialize-object (obj)
  "Generic materialization: change class in-place and register with BKNR.

CHANGE-CLASS preserves all slot values and object identity -- every
cross-reference (location, room-a, connections, contents, etc.) stays
valid because the same objects are still in memory.  INITIALIZE-INSTANCE
triggers BKNR's store-object registration (ID allocation, transaction
logging)."
  (let ((pclass (transient->persistent-class (class-of obj))))
    (change-class obj pclass)
    (initialize-instance obj)
    ;; INITIALIZE-INSTANCE sets up the store-object ID and transaction log
    ;; entry, but BKNR's INDEXED-CLASS MAKE-INSTANCE :AROUND method (which
    ;; adds the object to unique-index and class-skip-index) does not run
    ;; for CHANGE-CLASS objects.  Register manually so the object appears
    ;; in STORE-OBJECTS-WITH-CLASS and STORE-OBJECT-WITH-ID queries.
    (dolist (holder (bknr.indices::indexed-class-indices pclass))
      (bknr.indices:index-add (bknr.indices::index-holder-index holder) obj))
    obj))

(defun materialize-world (transient-world)
  "Convert TRANSIENT-WORLD into a persistent world in-place.

Every game object (rooms, connections, NPCs, guestbooks, puzzles) and the
world itself are converted to their persistent counterparts via
CHANGE-CLASS + INITIALIZE-INSTANCE.  Because object identity is preserved,
all cross-references remain valid without any fixup pass.

Characters (players) are excluded -- they are transient by nature and
never stored in the datastore.

Returns TRANSIENT-WORLD (now a persistent-world)."
  (build-persistent-class-map)
  (bknr.datastore:with-transaction ("materialize-world")
    ;; Convert all non-character game objects in-place
    (dolist (obj (world-all-objects transient-world))
      (unless (typep obj 'mud-character)
        (materialize-object obj)))
    ;; Convert the world itself via the same generic mechanism
    (materialize-object transient-world)
    ;; Ensure the id-counter is tracked in the transaction log
    (setf (world-id-counter transient-world) (world-id-counter transient-world)))
  transient-world)

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
      (connect-rooms! world gathering "north" forest "south")
      (connect-rooms! world gathering "east" desert "west")
      (connect-rooms! world gathering "west" swamp "east")
      (connect-rooms! world gathering "south" volcano "north")
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
