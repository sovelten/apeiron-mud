(in-package #:apeiron-test)

(in-suite persistence-suite)

(test world-initialization
  "Test that the world initializes properly"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (is (not (null (apeiron.core:get-config-key world :starting-room-id))))
    (is (> (apeiron.core:world-total-rooms world) 0))))

(test persistent-class-registry
  "The declarative *PERSISTENT-CLASS-REGISTRY* defines a wrapping
persistent class for every registered transient class, and
TRANSIENT->PERSISTENT-CLASS resolves them without class-hierarchy
walking."
  (let ((expected
          '((mud-object . persistent-object)
            (mud-room . persistent-room)
            (mud-character . persistent-character)
            (limb . apeiron.persistence::persistent-limb)
            (mud-guestbook . persistent-guestbook)
            (mud-npc . apeiron.persistence::persistent-npc)
            (mud-wordle-puzzle . persistent-wordle)
            (mud-connection . persistent-connection)
            (mud-area . persistent-area)
            (mud-world . persistent-world)
            (apeiron.worlds:mud-decorator . apeiron.persistence::persistent-decorator))))
    (is (= (length expected) (hash-table-count *persistent-class-registry*))
        "Registry should have one entry per persistent class")
    (dolist (pair expected)
      (let* ((entry (gethash (car pair) *persistent-class-registry*)))
        (is-true entry "~A should be registered" (car pair))
        (is (eq (cdr pair)
                (class-name (transient->persistent-class (find-class (car pair)))))
            "TRANSIENT->PERSISTENT-CLASS should resolve ~A" (car pair)))))
  ;; The wrapping superclass structure is derived from the registry.
  (let ((room-supers (mapcar #'class-name (sb-mop:class-direct-superclasses
                                           (find-class 'persistent-room))))
        (limb-supers (mapcar #'class-name (sb-mop:class-direct-superclasses
                                           (find-class 'apeiron.persistence::persistent-limb)))))
    (is (member 'mud-room room-supers))
    (is (member 'persistent-object room-supers)
        "MUD-OBJECT subtypes wrap PERSISTENT-OBJECT")
    (is (member 'limb limb-supers))
    (is (member 'persistent-object limb-supers)
        "LIMB is a MUD-OBJECT subtype, so its wrapper inherits PERSISTENT-OBJECT"))
  ;; Transient-slot metadata is recorded per class (slots are matched by
  ;; symbol name, so compare by name here too).
  (is (equal '("CONTENTS")
             (mapcar #'symbol-name
                     (gethash :transient-slots (gethash 'mud-room *persistent-class-registry*)))))
  (is (equal '("CHARACTERS" "OBJECTS" "ROOMS" "AREAS" "PARSER")
             (mapcar #'symbol-name
                     (gethash :transient-slots (gethash 'mud-world *persistent-class-registry*))))))

(test persistent-class-schemas-stable
  "Persistent class schema fingerprints are deterministic and stay
unchanged when the classes are redefined from the same registry — the
signal SAFE-UPDATE uses to decide whether a second snapshot is needed
after a reload."
  (let ((schemas (apeiron.persistence::persistent-class-schemas)))
    (is (= 11 (length schemas))
        "One schema fingerprint per registered class")
    (is (equal schemas (apeiron.persistence::persistent-class-schemas))
        "Fingerprints must be deterministic")
    ;; Redefining every class from the same registry must not change them.
    (define-persistent-classes *persistent-class-registry*)
    (is (equal schemas (apeiron.persistence::persistent-class-schemas))
        "Same registry data → same schema, so no extra snapshot needed")))

(test persistent-class-schema-change-detection
  "SAFE-UPDATE's 'snapshot again' decision (CLASSES-CHANGED-SINCE-P)
triggers on real schema changes and not on identical redefinitions."
  (let* ((transient-name (intern "MUD-SCHEMA-TEST-THING" :apeiron-test))
         (registry (serapeum:dict transient-name (serapeum:dict))))
    (eval `(defclass ,transient-name () ((data :initform nil))))
    (define-persistent-classes registry)
    (let ((before (apeiron.persistence::persistent-class-schemas registry)))
      ;; Identical redefinition must not change the schema.
      (define-persistent-classes registry)
      (is (not (apeiron.persistence::classes-changed-since-p before registry))
          "Identical redefinition → same schema → no snapshot")
      ;; Marking DATA transient is a real schema change.
      (setf (gethash :transient-slots (gethash transient-name registry)) '(data))
      (define-persistent-classes registry)
      (is (apeiron.persistence::classes-changed-since-p before registry)
          "Adding a transient slot changes the schema → snapshot"))))

(test class-change-snapshot-and-restore
  "The class-change scenario SAFE-UPDATE is designed for: when persistent
class schemas change, the second snapshot persists the new schema so it
survives a restart."
  (let* ((transient-name (intern "MUD-SCHEMA-EVOLVE-THING" :apeiron-test))
         (pname (intern "PERSISTENT-SCHEMA-EVOLVE-THING" :apeiron.persistence))
         (registry (serapeum:dict transient-name (serapeum:dict))))
    (unwind-protect
         (progn
           ;; Throwaway transient class with one slot.
           (eval `(defclass ,transient-name ()
                    ((data :initform "v1"))))
           (define-persistent-classes registry)
           ;; Live store with one instance of the wrapper class.
           (world-restore-or-initialize :force-new t)
           (let* ((obj (bknr.datastore:with-transaction ("schema-evolve-create")
                         (make-instance pname)))
                  (before (apeiron.persistence::persistent-class-schemas registry)))
             (is (equal "v1" (slot-value obj 'data)))
             (sync-world)              ; first snapshot (baseline)
             ;; Code changes: the transient class gains a slot and the
             ;; wrapper is redefined — exactly what a registry edit plus a
             ;; reload does.
             (eval `(defclass ,transient-name ()
                      ((data :initform "v1")
                       (extra :initform "v2"))))
             (define-persistent-classes registry)
             ;; SAFE-UPDATE's decision: classes changed → snapshot again.
             (is (apeiron.persistence::classes-changed-since-p before registry)
                 "Class change must trigger the second snapshot")
             ;; BKNR updated the live instance in place.
             (is (equal "v2" (slot-value obj 'extra)))
             (sync-world)              ; second snapshot with the new schema
             ;; Restart: the new schema must survive.
             (bknr.datastore:close-store)
             (world-restore-or-initialize)
             (let ((restored (first (bknr.datastore:store-objects-with-class pname))))
               (is-true restored "Restored instance of the changed class")
               (is (equal "v1" (slot-value restored 'data)))
               (is (equal "v2" (slot-value restored 'extra))
                   "Slot added by the class change survives the restore"))))
      ;; Cleanup.
      (ignore-errors
       (when (and (boundp 'bknr.datastore:*store*) bknr.datastore:*store*)
         (ignore-errors (bknr.datastore:close-store))
         (makunbound 'bknr.datastore:*store*))))))

(test bknr-id-conflict-on-restart
  "Test that world-level IDs do NOT conflict after store close/reopen."
  (unwind-protect
       (let* ((world (apeiron.persistence:world-restore-or-initialize
                      :force-new t :initializer #'test-world-with-rooms))
              (initial-ids (mapcar #'apeiron.core:object-id
                                   (apeiron.core:world-all-rooms world))))

         (is (>= (length initial-ids) 2))

         ;; Simulate restart: close store and restore
         (bknr.datastore:close-store)
         ;; characters is a transient slot — auto-initialized on restore

         (let* ((new-world (apeiron.persistence:world-restore-or-initialize
                            :initializer #'test-world-with-rooms))
                (restored-ids (mapcar #'apeiron.core:object-id
                                      (apeiron.core:world-all-rooms new-world))))
           ;; Ensure rooms were loaded with their original world-level IDs
           (is (= (length initial-ids) (length restored-ids)))
           (is (subsetp initial-ids restored-ids))
           ;; Add a new room post-restart
           (let ((new-room (apeiron.core:new-room :name "Post-Restart Room")))
             (apeiron.core:world-add-object! new-world new-room)
             (let ((new-id (apeiron.core:object-id new-room)))
               (is (not (member new-id restored-ids))
                   "New object ID ~D conflicts with existing loaded room IDs: ~A"
                   new-id restored-ids)))))))

(test id-counter-after-materialization
  "After materializing a world, the persistent world's id-counter must
reflect the transient world's counter so new objects don't get duplicate IDs."
  (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
         (max-id (loop for obj in (apeiron.core:world-all-objects world)
                       maximize (apeiron.core:object-id obj)))
         (new-room (apeiron.core:new-room :name "Latecomer")))
    (apeiron.core:world-add-object! world new-room)
    (let ((new-id (apeiron.core:object-id new-room)))
      (is (> new-id max-id)
          "New room ID ~D should exceed the highest existing ID ~D"
          new-id max-id))))

(test connections-not-duplicated-after-restore
  "After closing and reopening the BKNR store, a room's connections list
must not contain duplicates.  Connections are persisted in the store and
INITIALIZE-TRANSIENT-INSTANCE pushes again on restore, so without marking
the slot transient each restore doubles the list."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                  :force-new t :initializer #'test-world-with-rooms))
         (hub (apeiron.core:starting-room world)))
    ;; test-world-with-rooms has 1 connection (north/south between forest and tavern)
    (is (= 1 (length (apeiron.core:room-connections hub)))
        "Should have exactly 1 connection before restart")
    ;; First restart
    (apeiron.persistence:sync-world)
    (bknr.datastore:close-store)
    (let* ((new-world (apeiron.persistence:world-restore-or-initialize
                       :initializer #'test-world-with-rooms))
           (reloaded (apeiron.core:starting-room new-world)))
      (is (= 1 (length (apeiron.core:room-connections reloaded)))
          "After 1st restart: should have 1 connection, not ~D"
          (length (apeiron.core:room-connections reloaded)))
      ;; Second restart — this often reveals the duplication
      (apeiron.persistence:sync-world)
      (bknr.datastore:close-store)
      (let* ((newer-world (apeiron.persistence:world-restore-or-initialize
                           :initializer #'test-world-with-rooms))
             (reloaded2 (apeiron.core:starting-room newer-world)))
        (is (= 1 (length (apeiron.core:room-connections reloaded2)))
            "After 2nd restart: should have 1 connection, not ~D"
            (length (apeiron.core:room-connections reloaded2)))))))

(test connect-rooms-on-persistent-world-no-duplicate
  "connect-rooms! on a persistent world must not duplicate connections
in the room's connections list."
  (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
         (gathering (apeiron.core:starting-room world))
         (count-before (length (apeiron.core:room-connections gathering)))
         (new-room (apeiron.core:create-object! world (apeiron.core:new-room :name "Secret"))))
    (apeiron.core:connect-rooms! world gathering new-room
                                 :to "west" :from "east")
    (is (= (1+ count-before)
           (length (apeiron.core:room-connections gathering)))
        "Expected ~D connections after adding one, got ~D"
        (1+ count-before)
        (length (apeiron.core:room-connections gathering)))))

(test guestbook-persistence
  "Test that guestbook entries survive store close/reopen via CSV persistence."
  ;; Clean up any leftover CSV from earlier runs
  (let ((csv-path (merge-pathnames "guestbook.csv" *data-directory*)))
    (when (probe-file csv-path)
      (delete-file csv-path)))
  (unwind-protect
       ;; Find the guestbook in the starting room
       (let* ((world (apeiron.persistence:world-restore-or-initialize
                      :force-new t :initializer #'test-world-with-rooms))
              (tavern (apeiron.core:starting-room world))
              (guestbook (find-if (lambda (obj) (typep obj 'apeiron.core:mud-guestbook))
                                  (apeiron.core:container-all-objects tavern))))

         (is (not (null guestbook)))

         ;; Add an entry (writes to CSV on disk)
         (apeiron.core:guestbook-add-entry guestbook "Sophia" "Persistent via CSV!")

         ;; Snapshot
         (apeiron.persistence:sync-world)

         ;; Simulate restart
         (bknr.datastore:close-store)
         ;; characters is a transient slot — auto-initialized on restore
         ;; Find the guestbook in the restored world
         (let* ((new-world (apeiron.persistence:world-restore-or-initialize
                            :initializer #'test-world-with-rooms))
                (reloaded-tavern (apeiron.core:starting-room new-world))
                (reloaded-gbook (find-if (lambda (obj) (typep obj 'apeiron.core:mud-guestbook))
                                         (apeiron.core:container-all-objects reloaded-tavern))))
           (is (not (null reloaded-gbook)))
           (let ((entries (apeiron.core:guestbook-entries reloaded-gbook)))
             (is (= (length entries) 1))
             (is (equal (getf (first entries) :author) "Sophia"))
             (is (equal (getf (first entries) :message) "Persistent via CSV!")))))
    ;; Clean up CSV file after test
    (let ((csv-path (merge-pathnames "guestbook.csv" *data-directory*)))
      (when (probe-file csv-path)
        (ignore-errors (delete-file csv-path))))))

(test properties-tracked-via-slot-write
  "object-set-property on a persistent object must write the slot
so BKNR records the change in the transaction log."
  (let* ((world (world-restore-or-initialize :force-new t))
         (transient-obj (new-object :name "test-prop"))
         (obj (progn (world-add-object! world transient-obj)
                     (create-object! world transient-obj))))
    ;; Set a property — should trigger a slot write via the method
    (object-set-property obj "color" "blue")
    ;; Verify the value is set
    (is (equal "blue" (object-get-property obj "color")))
    ;; Verify the property is in the hash-table
    (is (equal "blue" (gethash "color" (object-properties obj))))))

(test properties-survive-snapshot-restart
  "Object properties set via object-set-property on a persistent object
must survive a snapshot + close-store + reopen cycle."
  (let* ((world (world-restore-or-initialize :force-new t))
         (obj (create-object! world (new-object :name "restore-prop-test"))))
    (object-set-property obj "color" "green")
    (bknr.datastore:close-store)
    (let* ((new-world (world-restore-or-initialize))
           (restored (world-object-by-id new-world (object-id obj))))
      (is (not (null restored))
          "Object should be found after restart")
      (is (equal "green" (object-get-property restored "color"))
          "Property should survive snapshot + restart"))))

(test create-object!-with-room-on-persistent-world
  "create-object! with the optional ROOM argument materializes the object
and places it in the room (location set + added to room contents).  The
placement must survive a snapshot + restart."
  (unwind-protect
       (let* ((world (world-restore-or-initialize :force-new t))
              (room (starting-room world))
              (obj (create-object! world (new-object :name "Persistent Vase") room)))
         ;; Materialized into the datastore and placed in the room.
         (is (typep obj 'persistent-object))
         (is (eq room (object-location obj)))
         (is (member obj (container-all-objects room) :test #'eq))
         ;; Registered in the world's object index.
         (is (eq obj (world-object-by-id world (object-id obj))))
         ;; Survives a snapshot + restart, still in the room's contents.
         (sync-world)
         (bknr.datastore:close-store)
         (let* ((new-world (world-restore-or-initialize))
                (restored (world-object-by-id new-world (object-id obj)))
                (new-room (starting-room new-world)))
           (is (not (null restored))
               "Object should be found after restart")
           (is (equal "Persistent Vase" (object-name restored)))
           (is (eq new-room (object-location restored))
               "Location should survive restart")
           (is (member restored (container-all-objects new-room) :test #'eq)
               "Object should remain in the room's contents after restart")))
    (ignore-errors
     (when (boundp 'bknr.datastore:*store*)
       (ignore-errors (bknr.datastore:close-store))
       (makunbound 'bknr.datastore:*store*)))))

(test guestbook-present-after-restore
  "After closing and reopening the BKNR store, the guestbook should still
be present in the starting room.  This guards against a bug where
CONTAINER-ADD-OBJECT did not set OBJECT-LOCATION, so the rebuild step
in WORLD-RESTORE-OR-INITIALIZE could not find the guestbook and it
disappeared from the room."
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t :initializer #'test-world-with-rooms))
         (tavern (apeiron.core:starting-room world)))

    ;; Guestbook should be in the room after first materialization
    (let ((gb-first (find-if (lambda (obj) (typep obj 'apeiron.core:mud-guestbook))
                             (apeiron.core:container-all-objects tavern))))
      (is (not (null gb-first))
          "Guestbook should be in the starting room after first materialization"))

    ;; Sync and restart
    (apeiron.persistence:sync-world)
    (bknr.datastore:close-store)

    (let* ((new-world (apeiron.persistence:world-restore-or-initialize
                       :initializer #'test-world-with-rooms))
           (reloaded-tavern (apeiron.core:starting-room new-world))
           (gb-after (find-if (lambda (obj) (typep obj 'apeiron.core:mud-guestbook))
                              (apeiron.core:container-all-objects reloaded-tavern))))
      (is (not (null gb-after))
          "Guestbook should still be in the starting room after BKNR restore"))))

(test unbound-persistent-slots-initialized-after-restore
  "When BKNR restores from a snapshot that predates the addition of a
persistent slot, that slot remains UNBOUND after restore (the snapshot
has no value for it and initforms are not applied during restore).
INITIALIZE-TRANSIENT-INSTANCE must reinitialize such slots from their
initforms so they do not cause SLOT-UNBOUND errors on access."
  ;; The user scenario: after restart, connection-find for any direction
  ;; must NOT signal SLOT-UNBOUND.  The test world's connections
  ;; are created with plain direction specs, so the direction slot is
  ;; bound — this is fine.  The bug only manifests when the slot is
  ;; genuinely UNBOUND (e.g. when a slot was added post-snapshot).
  (let* ((world (apeiron.persistence:world-restore-or-initialize
                 :force-new t :initializer #'test-world-with-biomes))
         (g (starting-room world)))
    ;; Verify connection-find returns a connection for primary directions
    (is (not (null (connection-find g "north"))) "Find north")
    (is (not (null (connection-find g "south"))) "Find south")
    (is (not (null (connection-find g "east"))) "Find east")
    (is (not (null (connection-find g "west"))) "Find west"))
  ;; After a full snapshot/restore cycle
  (apeiron.persistence:sync-world)
  (bknr.datastore:close-store)
  (let* ((world2 (apeiron.persistence:world-restore-or-initialize
                  :initializer #'test-world-with-biomes))
         (g2 (starting-room world2)))
    (is (not (null (connection-find g2 "north"))) "Find north after restore")
    (is (not (null (connection-find g2 "south"))) "Find south after restore")
    (is (not (null (connection-find g2 "east"))) "Find east after restore")
    (is (not (null (connection-find g2 "west"))) "Find west after restore"))
  ;; Simulate a slot added post-snapshot via slot-makunbound, then
  ;; verify that initialize-transient-instance re-initializes it.
  (let* ((world3 (apeiron.persistence:world-restore-or-initialize
                  :initializer #'test-world-with-biomes))
         (g3 (starting-room world3))
         (conn (first (room-connections g3))))
    (slot-makunbound conn 'apeiron.core::direction-a)
    (is-false (slot-boundp conn 'apeiron.core::direction-a) "unbound after makunbound")
    (bknr.datastore:initialize-transient-instance conn)
    (is-true (slot-boundp conn 'apeiron.core::direction-a) "re-bound after init")))

(test owned-character-survives-restart
  "An owned character created for an account now SURVIVES a service restart.
Characters are persisted in BKNR (PERSISTENT-CHARACTER) and restored into
the world's character index.  The account itself is also restored from
accounts.dat, with no character-slot link needed."
  (let* ((*data-directory* *data-directory*)
         (*store-directory* *store-directory*)
         (session (make-instance 'stream-session
                                 :stream (make-string-output-stream))))
    (unwind-protect
         (progn
           ;; ---- Phase 1: Create account + character --------------------
           (clrhash *accounts*)
           (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
                  (account (register-account "SurvivorPlayer" "s3cr3t!"
                                             :email "survivor@test.com"))
                  (character (new-character "SurvivorHero" session
                                            :owner (account-name account))))
             ;; Use create-object! + place-character! (what handle-client does)
             (create-object! world character)
             (place-character! world character)

             ;; Verify the initial state
             (is-true (account-exists-p "SurvivorPlayer")
                      "Account should exist before restart")
             (is (equal "SurvivorHero" (object-name character))
                 "Character name should be set")
             (is (= 1 (world-total-characters world))
                 "World should have one character before restart")
             (is-true (character-owner character)
                      "Character should have an owner before restart"))

           ;; ---- Phase 2: Simulate service restart ----------------------
           (save-accounts)
           (apeiron.persistence:sync-world)
           (bknr.datastore:close-store)
           (clrhash *accounts*)

           (is (= 0 (hash-table-count *accounts*))
               "In-memory accounts cleared after simulated restart")

           ;; ---- Phase 3: Restore after restart -------------------------
           (load-accounts)
           (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
                  (restored-account (find-account "SurvivorPlayer"))
                  (restored-chars (loop for c being the hash-values
                                         of (world-characters new-world)
                                       collect c)))

             ;; Account survived
             (is-true (account-exists-p "SurvivorPlayer")
                      "Account should exist after restart")
             (is-true (authenticate-account "SurvivorPlayer" "s3cr3t!")
                      "Password should still verify after restart")

             ;; Character SURVIVED the restart — it's in the world
             (is (= 1 (length restored-chars))
                 "World should have one character after restart (the owned one)")
             (is (equal "SurvivorHero" (object-name (first restored-chars)))
                 "Character name should be preserved after restart")
             (is (equal "SurvivorPlayer"
                        (character-owner (first restored-chars)))
                 "Character owner should be preserved after restart")

             ;; Character is in BKNR as a persistent-character
             (is (= 1 (length (bknr.datastore:store-objects-with-class
                               'apeiron.persistence:persistent-character)))
                 "The owned character exists as a persistent-character in the datastore")))

      ;; ---- Cleanup ----------------------------------------------------
      (ignore-errors
       (when (boundp 'bknr.datastore:*store*)
         (ignore-errors (bknr.datastore:close-store))
         (makunbound 'bknr.datastore:*store*))
       (clrhash *accounts*)))))

(test owned-character-survives-crash
  "An owned character must survive a server crash (close-store without sync).
The transaction log — not the snapshot — should allow recovery of the
character with its name, owner, location, and index membership intact."
  (let* ((*data-directory* *data-directory*)
         (*store-directory* *store-directory*)
         (session (make-instance 'stream-session
                                 :stream (make-string-output-stream))))
    (unwind-protect
         (progn
           ;; ---- Phase 1: Create account + character --------------------
           (clrhash *accounts*)
           (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
                  (account (register-account "CrashHero" "p4ssw0rd!"
                                             :email "crash@test.com"))
                  (character (new-character "CrashTestDummy" session
                                            :owner (account-name account))))
             (create-object! world character)
             (place-character! world character)
             (is (equal "CrashTestDummy" (object-name character)))
             (is-true (character-owner character))
             (is (= 1 (world-total-characters world))))

           ;; ---- Phase 2: Simulate crash (close without sync) ----------
           (save-accounts)
           ;; Deliberately NO sync-world here — simulates a crash.
           (bknr.datastore:close-store)
           (clrhash *accounts*)

           ;; ---- Phase 3: Restore after crash ---------------------------
           (load-accounts)
           (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
                  (restored-chars (loop for c being the hash-values
                                         of (world-characters new-world)
                                       collect c)))
             (is-true (account-exists-p "CrashHero")
                      "Account should survive a crash")
             (is (= 1 (length restored-chars))
                 "Owned character should survive a crash (transaction log recovery)")
             (let ((c (first restored-chars)))
               (is (equal "CrashTestDummy" (object-name c))
                   "Character name should survive a crash")
               (is (equal "CrashHero" (character-owner c))
                   "Character owner should survive a crash")
               (is (not (null (object-location c)))
                   "Character location should survive a crash"))))

      ;; ---- Cleanup ----------------------------------------------------
      (ignore-errors
       (when (boundp 'bknr.datastore:*store*)
         (ignore-errors (bknr.datastore:close-store))
         (makunbound 'bknr.datastore:*store*))
       (clrhash *accounts*)))))

(test guest-character-not-restored-after-crash
  "Guest characters ARE persisted in BKNR during a session, but they are
deleted during world restore — only owned characters survive a crash."
  (let* ((*data-directory* *data-directory*)
         (*store-directory* *store-directory*)
         (session (make-instance 'stream-session
                                 :stream (make-string-output-stream))))
    (unwind-protect
         (progn
           (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
                  (character (new-character "GuestCrashTest" session
                                            :owner nil)))
             (create-object! world character)
             (place-character! world character)
             (is (= 1 (world-total-characters world)))
             (is (null (character-owner character))))

           ;; Simulate crash — no sync
           (bknr.datastore:close-store)

           (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
                  (restored-chars (loop for c being the hash-values
                                         of (world-characters new-world)
                                       collect c)))
             (is (= 0 (length restored-chars))
                 "Guest characters should NOT survive a crash")))
      ;; ---- Cleanup ----------------------------------------------------
      (ignore-errors
       (when (boundp 'bknr.datastore:*store*)
         (ignore-errors (bknr.datastore:close-store))
         (makunbound 'bknr.datastore:*store*))))))

(test area-persistence
  "Areas survive a snapshot + restore, stay indexed in the world, and
  have their cl-graph index rebuilt after restore."
  (unwind-protect
       (let* ((world (apeiron.persistence:world-restore-or-initialize
                      :force-new t :initializer #'test-world-with-area))
              (area (apeiron.core:world-area-with-name world "Test Cavern")))
         (is (not (null area)))
         (is (typep area 'apeiron.persistence:persistent-area))
         (is (= 3 (apeiron.core:area-room-count area)))
         (is (= 2 (apeiron.core:area-connection-count area)))
         (is (= 1 (apeiron.core:world-total-areas world)))

         ;; graph functional before restart
         (let ((entrance (apeiron.core:starting-room world)))
           (is (typep entrance 'apeiron.persistence:persistent-room))
           (is (equal (list "Cavern Entrance" "Great Hall" "Treasure Vault")
                      (mapcar #'apeiron.core:object-name
                              (apeiron.core:area-shortest-path
                               area entrance
                               (apeiron.core:area-find-room area "Treasure Vault"))))))

         ;; Simulate restart: snapshot, close, restore
         (apeiron.persistence:sync-world)
         (bknr.datastore:close-store)
         (let* ((new-world (apeiron.persistence:world-restore-or-initialize
                            :initializer #'test-world-with-area))
                (restored (apeiron.core:world-area-with-name new-world "Test Cavern")))
           (is (not (null restored))
               "Area should survive the restart")
           (is (typep restored 'apeiron.persistence:persistent-area))
           (is (= 1 (apeiron.core:world-total-areas new-world)))
           (is (= 3 (apeiron.core:world-total-rooms new-world)))
           (is (= 3 (apeiron.core:area-room-count restored)))
           (is (= 2 (apeiron.core:area-connection-count restored)))
           ;; the entrance survived and points at the restored room
           (is (typep (apeiron.core:area-entrance restored)
                      'apeiron.persistence:persistent-room))
           (is (equal "Cavern Entrance"
                      (apeiron.core:object-name (apeiron.core:area-entrance restored))))

           ;; graph was rebuilt from the restored connections
           (let ((entrance (apeiron.core:area-find-room restored "Cavern Entrance"))
                 (hall (apeiron.core:area-find-room restored "Great Hall"))
                 (treasure (apeiron.core:area-find-room restored "Treasure Vault")))
             (is (equal (list entrance hall treasure)
                        (apeiron.core:area-shortest-path restored entrance treasure)))
             ;; the one-way property survived and is respected by the rebuilt graph
             (is (null (apeiron.core:area-shortest-path restored treasure entrance)))
             (is (equal (list entrance hall treasure)
                        (sort (apeiron.core:area-reachable-rooms restored entrance)
                              #'string< :key #'apeiron.core:object-name))))))
      ;; ---- Cleanup ----------------------------------------------------
      (ignore-errors
       (when (boundp 'bknr.datastore:*store*)
         (ignore-errors (bknr.datastore:close-store))
         (makunbound 'bknr.datastore:*store*)))))

(test incremental-area-building-on-persistent-world
  "An already-registered persistent area can be extended incrementally:
  AREA-ADD-ROOM! with a fresh transient room and AREA-CONNECT-NORTH-SOUTH!
  with a fresh connection must register those objects with the world
  (materializing them for the datastore) instead of leaving them transient
  and tripping BKNR's ENCODE-OBJECT.  Regression test: the room and the
  connection used to be stored into the persistent area's slots while still
  plain MUD-ROOM / MUD-CONNECTION instances, which has no ENCODE-OBJECT
  method and failed with 'no applicable method'."
  (unwind-protect
       (let* ((world (apeiron.persistence:world-restore-or-initialize
                      :force-new t
                      :initializer (lambda ()
                                     (let ((w (apeiron.core:new-world)))
                                       (let ((r (apeiron.core:new-room :name "Bare Nexus")))
                                         (apeiron.core:world-add-object! w r)
                                         (apeiron.core:world-set-starting-room! w r))
                                       w))))
              (area (apeiron.core:new-area :name "Vila Incremental")))
         ;; Register an EMPTY area, then extend it incrementally — exactly
         ;; the in-game eval workflow that used to fail.
         (apeiron.core:world-add-area! world area)
         (is (= 1 (apeiron.core:world-total-areas world)))
         (is (eq world (apeiron.core:area-world area)))
         (let ((entrada (apeiron.core:new-room :name "Entrada"
                                               :description "A portal into Vila."))
               (pracinha (apeiron.core:new-room :name "Pracinha"
                                                :description "A small square.")))
           ;; Fresh transient rooms — no prior CREATE-OBJECT! — must be
           ;; materialized by AREA-ADD-ROOM! itself.
           (apeiron.core:area-add-room! area entrada)
           (apeiron.core:area-add-room! area pracinha)
           (is (typep entrada 'apeiron.persistence:persistent-room))
           (is (typep pracinha 'apeiron.persistence:persistent-room))
           (is (eq area (apeiron.core:world-area-of-room world entrada)))
           ;; The connection created from scratch by the cardinal helper
           ;; must be materialized too (like WORLD-CONNECT-ROOMS!).
           (apeiron.core:area-connect-north-south! area entrada pracinha)
           (is (= 2 (apeiron.core:area-room-count area)))
           (is (= 1 (apeiron.core:area-connection-count area)))
           (let ((conn (first (apeiron.core:area-room-connections area entrada))))
             (is (not (null conn)))
             (is (typep conn 'apeiron.persistence:persistent-connection)))
           ;; Movement through the area works immediately.
           (is (eq pracinha (apeiron.core:room-exit-target entrada "south")))
           (is (eq entrada (apeiron.core:room-exit-target pracinha "north")))
           ;; The incrementally added content survives a snapshot + restart.
           (apeiron.persistence:sync-world)
           (bknr.datastore:close-store)
           (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
                  (restored (apeiron.core:world-area-with-name
                             new-world "Vila Incremental")))
             (is (not (null restored)))
             (is (= 2 (apeiron.core:area-room-count restored)))
             (is (= 1 (apeiron.core:area-connection-count restored)))
             (is (eq new-world (apeiron.core:area-world restored))
                 "Restored area must know its world again")
             (let ((restored-entrada (apeiron.core:area-find-room restored "Entrada"))
                   (restored-pracinha (apeiron.core:area-find-room restored "Pracinha")))
               (is (typep restored-entrada 'apeiron.persistence:persistent-room))
               (is (typep restored-pracinha 'apeiron.persistence:persistent-room))
               (is (eq restored-pracinha
                       (apeiron.core:room-exit-target restored-entrada "south"))
                   "Connection must survive the restart")))))
    ;; ---- Cleanup ----------------------------------------------------
    (ignore-errors
     (when (boundp 'bknr.datastore:*store*)
       (ignore-errors (bknr.datastore:close-store))
       (makunbound 'bknr.datastore:*store*)))))
