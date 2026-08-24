;;;; src/persistence/persistent-world.lisp — BKNR datastore persistence for the MUD world

(in-package :apeiron.persistence)

;; ─── Persistent wrapper classes ──────────────────────────────────────────────
;;
;; The PERSISTENT-* classes are declared as data in registry.lisp via
;; *PERSISTENT-CLASS-REGISTRY*.  That file is loaded before this one, so the
;; classes already exist when the DEFMETHODs below are compiled; they only
;; specialize on them.

(defmethod bknr.datastore:initialize-transient-instance ((gb persistent-guestbook))
  "Re-read guestbook entries from the CSV file after restore."
  (call-next-method)
  (let ((fp (guestbook-filepath gb)))
    (when fp
      (setf (guestbook-entries gb)
            (guestbook-load-from-csv (pathname fp))))))

(defmethod bknr.datastore:initialize-transient-instance :after ((obj persistent-object))
  "After restoring from a snapshot, initialize any unbound slots using
their initfunctions.  Slots added to a persistent class after the last
snapshot was taken have no stored value and remain unbound after the
standard restore process — this method ensures they get their initform
values so they don't cause SLOT-UNBOUND errors on access."
  (dolist (slotd (sb-mop:class-slots (class-of obj)))
    (let ((name (sb-mop:slot-definition-name slotd))
          (initfn (sb-mop:slot-definition-initfunction slotd)))
      (when (and initfn (not (slot-boundp obj name)))
        (setf (slot-value obj name) (funcall initfn))))))

(defmethod bknr.datastore:initialize-transient-instance :after ((obj persistent-character))
  "Make sure a restored character's limbs are persistent store-objects.

Characters saved before the limbs feature had no stored LIMBS value, so
the PERSISTENT-OBJECT method above filled the slot with fresh transient
limbs from the initform.  Converting them in place here means wearing and
removing items afterwards is tracked by the datastore."
  (dolist (limb (character-limbs obj))
    (unless (typep limb 'bknr.datastore:store-object)
      (materialize-object limb))))

(defmethod bknr.datastore:initialize-transient-instance :after ((area persistent-area))
  "Rebuild the area's cl-graph index from its restored rooms and
connections.  The graph is a transient slot and is not stored in the
snapshot, so it must be reconstructed after every restore."
  (area-rebuild-graph! area))

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

(defmethod create-object! ((world persistent-world) object &optional room)
  "Register OBJECT in WORLD by converting it to a persistent object in-place.
The transient OBJECT is converted in-place via MATERIALIZE-OBJECT, which
uses CHANGE-CLASS to preserve slot values and object identity.
Already-persistent objects (e.g., reconnected characters) are registered
directly without re-materialization.
When ROOM is provided, OBJECT is also placed in ROOM (location set and
added to ROOM's contents) inside the same transaction."
  (bknr.datastore:with-transaction ("create-object")
    (unless (typep object 'bknr.datastore:store-object)
      (materialize-object object)
      ;; CHANGE-CLASS preserves slot values without going through
      ;; (SETF SLOT-VALUE), so BKNR never records them in the
      ;; transaction log.  Touch every persistent slot so its value
      ;; is persisted and survives a crash without sync-world.
      (let ((transient-slots (class-transient-slots (class-of object))))
        (dolist (slotd (sb-mop:class-slots (class-of object)))
          (let ((sname (sb-mop:slot-definition-name slotd)))
            (when (and (not (member sname transient-slots))
                       (slot-boundp object sname))
              (setf (slot-value object sname)
                    (slot-value object sname)))))))
    (world-add-object! world object)
    (when room
      (container-add-object room object)))
  object)

(defmethod world-remove-object! ((world persistent-world) object)
  "Remove OBJECT from world indices and destroy it in the BKNR datastore.
When OBJECT is a character, its persistent limb store-objects are
destroyed too (a character owns its limbs), preventing leaked limbs."
  (bknr.datastore:with-transaction ("remove-object")
    (call-next-method)
    (when (and (typep object 'bknr.datastore:store-object)
               (not (bknr.indices:object-destroyed-p object)))
      ;; A character's limbs are owned store-objects: delete them along
      ;; with the character, otherwise they leak in the datastore.
      (when (typep object 'mud-character)
        (dolist (limb (character-limbs object))
          (when (typep limb 'bknr.datastore:store-object)
            (bknr.datastore:delete-object limb))))
      (bknr.datastore:delete-object object)))
  object)

(defmethod world-add-area! ((world persistent-world) area)
  "Register AREA and everything in it with a persistent WORLD.

Materializes the whole area closure (rooms, contained objects,
connections, and the area itself) into the BKNR datastore in ONE
transaction before indexing it in the world.

CREATE-OBJECT! per object would be the wrong tool here: it materializes
each object and then touches every persistent slot to force it into the
transaction log.  Rooms carry a ROOM-AREA back-reference to the area, so
if rooms are materialized before the area, that touch tries to
ENCODE-OBJECT a still-transient MUD-AREA — which has no encoder and
fails.  Materializing everything together (as MATERIALIZE-WORLD does)
defers slot encoding until every object is persistent.

Enforces the one-area-per-room invariant first.  Returns AREA."
  ;; Enforce the one-area-per-room invariant before mutating anything.
  (dolist (room (area-room-list area))
    (let ((owner (world-area-of-room world room)))
      (when (and owner (not (eq owner area)))
        (error "world-add-area!: room ~A already belongs to area ~A; a room can only belong to one area."
               (object-name room) (object-name owner)))))
  (bknr.datastore:with-transaction ("add-area")
    ;; Materialize rooms and their contents and connections FIRST, then
    ;; the area.  The area's ROOMS slot is encoded into the transaction
    ;; log when the area is materialized, so by then every room must
    ;; already be a persistent store-object — otherwise ENCODE-OBJECT
    ;; gets a still-transient MUD-ROOM and fails.
    (dolist (room (area-room-list area))
      (materialize-object room))
    (dolist (room (area-room-list area))
      (dolist (obj (container-all-objects room))
        (unless (typep obj 'mud-character)
          (materialize-object obj))))
    (dolist (conn (area-connections area))
      (materialize-object conn))
    (materialize-object area))
  ;; Now index everything in the world (IDs are already assigned by BKNR;
  ;; WORLD-ADD-OBJECT! registers into the world's hash tables).
  (dolist (room (area-room-list area))
    (world-add-object! world room))
  (dolist (room (area-room-list area))
    (dolist (obj (container-all-objects room))
      (unless (typep obj 'mud-character)
        (world-add-object! world obj))))
  (dolist (conn (area-connections area))
    (world-add-object! world conn))
  (world-add-object! world area)
  ;; Record the owning world so incremental AREA-ADD-ROOM! /
  ;; AREA-REGISTER-CONNECTION! calls can register new content with it.
  (setf (area-world area) world)
  area)

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

(defun persistent-class-schema (class)
  "Return a canonical fingerprint of CLASS's persistent schema: its
name, the name and transient flag of every effective slot, and its
direct superclasses.  Used by SAFE-UPDATE to detect whether a reload
changed the datastore schema."
  (list (class-name class)
        (mapcar (lambda (slotd)
                  (list (sb-mop:slot-definition-name slotd)
                        (bknr.datastore::transient-slot-p slotd)))
                (sb-mop:class-slots class))
        (mapcar #'class-name (sb-mop:class-direct-superclasses class))))

(defun persistent-class-schemas (&optional (registry *persistent-class-registry*))
  "Fingerprints of every persistent class declared in REGISTRY (default
*PERSISTENT-CLASS-REGISTRY*), sorted by class name so two snapshots of
the same schema compare EQUAL."
  (sort (loop for transient-name being each hash-key
                of registry
                using (hash-value options)
              for pname = (persistent-class-name transient-name options)
              for class = (find-class pname nil)
              when class
                collect (persistent-class-schema class))
        #'string<
        :key (lambda (schema) (symbol-name (first schema)))))

(defun classes-changed-since-p (schemas &optional (registry *persistent-class-registry*))
  "True if the persistent class schemas in REGISTRY (default
*PERSISTENT-CLASS-REGISTRY*) differ from SCHEMAS.  SAFE-UPDATE uses this
to decide whether a reload changed the datastore schema and a second
snapshot is needed."
  (not (equal schemas (persistent-class-schemas registry))))

(defun safe-update ()
  "Pull latest code changes into the running image safely.

Snapshots the datastore first as a safety baseline, so a broken reload
can be rolled back.  Then RELOAD-APEIRON reloads the changed APEIRON
systems, which re-runs DEFINE-PERSISTENT-CLASSES and redefines the
persistent classes from *PERSISTENT-CLASS-REGISTRY* whenever that file
changed.

A second snapshot is taken only when the persistent class schemas
actually changed — the situation BKNR warns about ('class ~A has been
changed ... please snapshot your datastore') — so the new schema is
persisted.  When no class changed, the first snapshot is still current
and the redundant second snapshot is skipped."
  (sync-world)
  (let ((before (persistent-class-schemas)))
    (reload-apeiron)
    (when (classes-changed-since-p before)
      (log-message "Persistent class definitions changed — snapshotting datastore for schema evolution.")
      (sync-world))))

;; ─── Persistent class mapping ───────────────────────────────────────────────

(defun transient->persistent-class (transient-class)
  "Return the persistent class that wraps TRANSIENT-CLASS.

The persistent class name is derived from TRANSIENT-CLASS's entry in
*PERSISTENT-CLASS-REGISTRY* (the declarative data in registry.lisp) —
no class-hierarchy walking needed."
  (let* ((transient-name (class-name transient-class))
         (entry (gethash transient-name *persistent-class-registry*)))
    (or (and entry (find-class (persistent-class-name transient-name entry)))
        (error "No persistent class registered for ~A -- add it to *PERSISTENT-CLASS-REGISTRY*."
               transient-class))))

;; ─── World materialization ──────────────────────────────────────────────────

(defgeneric materialize-object (obj)
  (:documentation
   "Convert OBJ into its persistent counterpart and register it with BKNR.

Dispatching on the class of OBJ allows adding new object types without
modifying this generic function -- just add a DEFWRAPPING-PERSISTENT-CLASS
and optionally specialize MATERIALIZE-OBJECT if extra steps are needed.

The persistent class is resolved through the global
*PERSISTENT-CLASS-REGISTRY* (see TRANSIENT->PERSISTENT-CLASS).

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

(defmethod materialize-object ((obj mud-character))
  "Materialize a character's limbs first, then the character itself.

The limbs (head/hand instances) are plain objects whose
CONTAINER-CONTENTS must be persisted.  Converting them to
PERSISTENT-LIMB store-objects before the character's LIMBS slot is
encoded lets BKNR track what the character wears."
  (dolist (limb (character-limbs obj))
    (unless (typep limb 'bknr.datastore:store-object)
      (materialize-object limb)))
  (call-next-method))

(defun materialize-world (transient-world)
  "Convert TRANSIENT-WORLD into a persistent world in-place.

Every game object (rooms, connections, NPCs, guestbooks, puzzles,
characters) and the world itself are converted to their persistent
counterparts via CHANGE-CLASS + INITIALIZE-INSTANCE.  Because object
identity is preserved, all cross-references remain valid without any
fixup pass.

Returns TRANSIENT-WORLD (now a persistent-world)."
  (bknr.datastore:with-transaction ("materialize-world")
    ;; Convert all game objects in-place (including characters)
    (dolist (obj (world-all-objects transient-world))
      (materialize-object obj))
    ;; Convert the world itself via the same generic mechanism
    (materialize-object transient-world)
    ;; Ensure the id-counter is tracked in the transaction log
    (setf (world-id-counter transient-world) (world-id-counter transient-world)))
  transient-world)

;; ─── World restore / initialize ─────────────────────────────────────────────

(defun default-transient-world ()
  "Create a bare transient world with the nexus room, a guestbook, and
some starter equipment (a wizard hat and a rusty sword).

Used as the fallback when WORLD-RESTORE-OR-INITIALIZE is called
without :TRANSIENT-WORLD."
  (let ((world (make-instance 'mud-world)))
    (let ((nexus (new-room :name "Apeiron Nexus"
                           :description "You are in a place outside of time and space. All possibilities and all things conjoin here. You can go everywhere, do everything. Be everything. What will you do?")))
      (container-add-object nexus (new-object :name "a wizard hat"
                                              :description "A pointy, midnight-blue wizard hat, dusted with tiny silver stars that seem to twinkle."
                                              :keywords '("hat" "wizard")
                                              :aliases '("hat" "wizard hat")))
      (container-add-object nexus (new-object :name "a rusty sword"
                                              :description "A battered blade, its edge nicked and its grip wrapped in frayed leather."
                                              :keywords '("weapon" "sword")
                                              :aliases '("sword")))
      (world-add-object! world nexus)
      (world-set-starting-room! world nexus))
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
          ;; Guest characters (no owner) don't survive crashes or
          ;; restarts — remove them via world-remove-object! which
          ;; handles its own transaction and destroyed-object guards.
          (let ((guests (remove-if-not
                         (lambda (o)
                           (and (typep o 'mud-character)
                                (guest? o)
                                (not (bknr.indices:object-destroyed-p o))))
                         (bknr.datastore:store-objects-with-class
                          'persistent-object))))
            (dolist (g guests)
              ;; Drop the guest's worn/carried items into their room
              ;; before destroying them, so the items are not orphaned.
              (drop-character-items! g)
              (world-remove-object! world g)))
          ;; Populate world indices and rebuild room contents from
          ;; surviving BKNR objects.
          (bknr.datastore:with-transaction ("restore-world")
            (dolist (obj (bknr.datastore:store-objects-with-class
                          'persistent-object))
              (unless (bknr.indices:object-destroyed-p obj)
                (world-add-object! world obj)
                ;; Restore the area→world back-reference so incremental
                ;; AREA-ADD-ROOM! / AREA-REGISTER-CONNECTION! calls work
                ;; after a restart.  Also covers areas whose snapshot
                ;; predates the WORLD slot (which restores as NIL).
                (when (typep obj 'persistent-area)
                  (setf (area-world obj) world))))
            (dolist (obj (bknr.datastore:store-objects-with-class
                          'persistent-object))
              (unless (bknr.indices:object-destroyed-p obj)
                (let ((location (object-location obj)))
                  (when (typep location 'persistent-room)
                    (container-add-object location obj))))))
          (when *debug-mode*
            (log-message "World restored from BKNR datastore."))
          world)
        (let* ((transient (funcall initializer))
               (world (materialize-world transient)))
          (sync-world)
          (when *debug-mode*
            (log-message "New world created from transient and persisted."))
          world))))
