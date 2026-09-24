;;;; src/persistence/migrations.lisp — Versioned datastore data migrations.
;;;;
;;;; The narrative documentation for this module lives in the
;;;; @DATA-MIGRATIONS section below.

(in-package :apeiron.persistence)

(named-readtables:in-readtable pythonic-string-syntax)

(defsection @data-migrations (:title "Data Migrations")
  """BKNR persists objects against the *class layout that existed when the
  snapshot / transaction was written*.  When code changes a persistent slot
  (rename, retype, remove), old datastores must be brought up to the current
  schema.  BKNR itself offers only limited hooks for this
  (`*slot-name-map*`, `CONVERT-SLOT-VALUE-WHILE-RESTORING`), and they run at
  decode time / interactively, which is not usable for automatic migration.

  This package therefore provides a small versioned migration framework:

  - `*DATA-MIGRATIONS*` — a registry of `DATA-MIGRATION` objects ordered by
    ascending `VERSION`.
  - `DEFINE-DATA-MIGRATION` / `REGISTER-DATA-MIGRATION` — add a migration to
    the registry.  Adding a *future* migration is purely additive: register a
    new migration with the next version number and it will run automatically
    — no changes to `SAFE-UPDATE`, `WORLD-RESTORE-OR-INITIALIZE`, or anything
    else are needed.
  - `CURRENT-DATA-VERSION` — the migration version recorded in the datastore
    (stored in the world's config under `:data-version`).  A datastore
    written before this mechanism exists has no such key and reads as
    version 0, so every migration runs in order on the next open.
  - `RUN-DATA-MIGRATIONS` — apply all registered migrations whose version is
    greater than the datastore's current version, in ascending order,
    snapshotting once at the end so the migrated data and the new version
    marker are durable.

  ### Runner invocation points

  `WORLD-RESTORE-OR-INITIALIZE` calls `RUN-DATA-MIGRATIONS` on an existing
  world *before* guest cleanup and index population, so migrated data is
  authoritative for everything downstream.  A fresh world is stamped with the
  latest version at creation.

  `SAFE-UPDATE` calls `RUN-DATA-MIGRATIONS` after a hot reload so migrations
  ship with new code and apply as soon as that code is loaded — but
  SAFE-UPDATE only invokes the generic runner, so future migrations never
  require editing SAFE-UPDATE itself.

  ### Why this is safe even when the running server's SAFE-UPDATE is the old
  version

  Migration is triggered by *opening the datastore with the new code*
  (`WORLD-RESTORE-OR-INITIALIZE` at startup / after a reload), which always
  executes the current code.  We never depend on the old SAFE-UPDATE knowing
  about a specific migration.

  ### Renaming slots and decode

  BKNR decodes an old snapshot against the current classes *before*
  RUN-DATA-MIGRATIONS runs.  A slot name from an old layout that no longer
  exists on the class will stop restore with an interactive
  rename/convert/ignore prompt — not something automatic migration can fix.
  A slot rename must therefore keep the old name decodable: either the class
  keeps a slot with the same symbol name (which is exactly what happened when
  mud-character's OWNER became the generic MUD-OBJECT OWNER), or a migration
  runs that depends on that same-name decode (v1 below)."""
  (*data-migrations* variable)
  (register-data-migration function)
  (define-data-migration macro)
  (current-data-version function)
  (latest-data-version function)
  (run-data-migrations function))

;; SYNC-WORLD is defined in persistent-world.lisp, which loads after this
;; file.  Proclaim it here so compiling RUN-DATA-MIGRATIONS does not warn
;; about the forward reference.
(declaim (ftype (function () t) sync-world))

(defstruct data-migration
  version
  name
  fn)

(defvar *data-migrations* nil
  "Registered data migrations, kept sorted by ascending VERSION.")

(defun latest-data-version ()
  "Return the highest migration version registered, or 0 if none."
  (if *data-migrations*
      (data-migration-version (car (last *data-migrations*)))
      0))

(defun register-data-migration (version name fn)
  "Add FN (a function of one argument, the persistent world) to the
migration registry under VERSION.  VERSION must be a positive integer.

The registry stays sorted by ascending VERSION.  Re-registering an
already-present VERSION replaces the old migration — this file is reloaded
on every hot reload, so idempotent registration is required."
  (setf *data-migrations*
        (sort (cons (make-data-migration :version version
                                         :name name
                                         :fn fn)
                    (remove version *data-migrations*
                            :key #'data-migration-version))
              #'<
              :key #'data-migration-version))
  version)

(defmacro define-data-migration (version name (world-var) &body body)
  "Define a data migration with VERSION and NAME.  BODY runs with
WORLD-VAR bound to the persistent world object while the datastore is
open; it may read and write BKNR store objects and the world config.

VERSION is a positive integer that must be greater than every previously
registered migration's version.  NAME is a human-readable string used in
log output.

Adding a new migration later only requires another DEFINE-DATA-MIGRATION
form — no changes to SAFE-UPDATE or the restore path."
  `(register-data-migration
    ,version ,name
    (lambda (,world-var)
      (declare (ignorable ,world-var))
      ,@body)))

;; ─── Version marker ─────────────────────────────────────────────────────────
;; The current data version is stored in the world's config under
;; :data-version.  Config is a persistent slot on PERSISTENT-WORLD and is an
;; FSET map, so the marker survives snapshots and restarts; a datastore
;; written before this mechanism has no such key and therefore reports
;; version 0.
;;
;; The version marker lives in the very structure (the config) that the FSET
;; migration converts, so reading and writing it must tolerate the legacy
;; hash-table representation: an old datastore decodes its config as a hash
;; table, and RUN-DATA-MIGRATIONS reads the version before any migration has
;; had a chance to convert it.

(defun hash-table->fset-map (table)
  "Return an FSET map holding the same entries as the hash TABLE, or an
empty map when TABLE is not a hash table.  Used to upgrade legacy hash-table
slots (object properties, world config) to FSET maps."
  (let ((map (fset:empty-map)))
    (when (hash-table-p table)
      (maphash (lambda (key value) (setf map (fset:with map key value))) table))
    map))

(defun current-data-version (world)
  "Return the data migration version recorded in WORLD's config, tolerating
the legacy hash-table config of a pre-FSET datastore.
A datastore written before version markers existed has no :data-version
key and reports 0."
  (let ((config (world-config world)))
    (or (if (fset:map? config)
            (fset:lookup config :data-version)
            (and (hash-table-p config) (gethash :data-version config)))
        0)))

(defun (setf current-data-version) (version world)
  "Record VERSION as WORLD's data migration version and persist it.
Must be called while the datastore is open; the write goes through the
normal persistent-slot path so BKNR logs it.  A legacy hash-table config is
converted to an FSET map here, so this is safe to call before the FSET
migration has run.

WORLD-CONFIG is an immutable FSET map: rebinding the slot with a new map is
itself the slot write BKNR records, so no separate self-write is needed."
  (let ((config (world-config world)))
    (setf (world-config world)
          (fset:with (if (fset:map? config) config (hash-table->fset-map config))
                     :data-version version)))
  version)

;; ─── Runner ─────────────────────────────────────────────────────────────────

(defun run-data-migrations (world)
  "Apply every registered data migration with version greater than WORLD's
current data version, in ascending order.

Runs each migration in its own transaction so a failing migration rolls
back cleanly, then advances the recorded version marker and snapshots the
datastore once at the end.  Returns the list of migrations that ran (each
as a DATA-MIGRATION), or NIL when nothing was pending."
  (let* ((start-version (current-data-version world))
         (pending (remove-if (lambda (m)
                               (<= (data-migration-version m) start-version))
                             *data-migrations*)))
    (dolist (migration (sort (copy-list pending)
                             #'< :key #'data-migration-version))
      (log-message "Running data migration ~D: ~A"
                   (data-migration-version migration)
                   (data-migration-name migration))
      ;; Run the migration and bump the recorded version in the SAME
      ;; transaction, so a failure rolls back both and the migration is
      ;; retried on the next open.
      (bknr.datastore:with-transaction
          ((format nil "data-migration-~D-~A"
                   (data-migration-version migration)
                   (data-migration-name migration)))
        (funcall (data-migration-fn migration) world)
        (setf (current-data-version world) (data-migration-version migration))))
    (when pending
      (log-message "Applied ~D pending data migration~:P." (length pending))
      (sync-world))
    pending))

;; ─── Concrete migrations ────────────────────────────────────────────────────
;; Each entry below fixes a specific historical datastore format.  Keep them
;; in ascending version order and never renumber or reorder existing ones.

(define-data-migration
    1 "rename-character-owner-to-account" (world)
  "Migrate datastores written before mud-character's OWNER slot was renamed
ACCOUNT (and a generic MUD-OBJECT OWNER slot was introduced).

Because the new class still has a slot whose symbol name is OWNER (the
generic object owner), BKNR decodes the old OWNER value into
OBJECT-OWNER on restore, while CHARACTER-ACCOUNT stays unbound and is
filled with its NIL initform.  This migration recognizes that legacy state
— a character with no ACCOUNT but a string OWNER — moves the value into
CHARACTER-ACCOUNT, and clears the generic OWNER so the re-snapshot is
clean.

Only runs on datastores whose recorded version is below 1 (i.e. created
before this migration shipped); fresh datastores are stamped at creation."
  (dolist (char (bknr.datastore:store-objects-with-class 'persistent-character))
    (unless (bknr.indices:object-destroyed-p char)
      (let ((account (character-account char))
            (owner (object-owner char)))
        (when (and (null account)
                   (stringp owner)
                   (plusp (length owner)))
          (setf (character-account char) owner)
          (setf (object-owner char) nil))))))

(define-data-migration
    2 "convert-properties-and-config-to-fset-maps" (world)
  "Migrate datastores written while object properties and the world config
were hash tables.

OBJECT-PROPERTIES and WORLD-CONFIG are now immutable FSET maps.  BKNR
decodes an old snapshot's hash-table value straight into the slot (it does
not type-check), so after restore every persistent object's PROPERTIES — and
the world's CONFIG — may still hold a hash table.  Convert them to FSET maps
so the accessors (FSET:LOOKUP / FSET:WITH) work.

The config is normally already converted by the version-marker writer (see
SETF CURRENT-DATA-VERSION), which runs before this migration body; the guard
here keeps the migration correct if it is ever the first to run.  Runs only
on datastores recorded below version 2; fresh datastores are stamped at
creation and skip it."
  ;; World config: convert if it is still a legacy hash table.
  (let ((config (world-config world)))
    (unless (fset:map? config)
      (setf (world-config world) (hash-table->fset-map config))))
  ;; Every live persistent object's properties.
  (dolist (obj (bknr.datastore:store-objects-with-class 'persistent-object))
    (unless (bknr.indices:object-destroyed-p obj)
      (let ((props (object-properties obj)))
        (unless (fset:map? props)
          (setf (object-properties obj) (hash-table->fset-map props)))))))
