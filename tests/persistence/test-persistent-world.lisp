(in-package #:apeiron-test)

(in-suite persistence-suite)

(test world-initialization
  "Test that the world initializes properly"
  (let ((world (apeiron.persistence:world-restore-or-initialize)))
    (is (not (null (apeiron.core:get-config-key world :starting-room-id))))
    (is (> (apeiron.core:world-total-rooms world) 0))))

(test bknr-id-conflict-on-restart
  "Test that world-level IDs do NOT conflict after store close/reopen."
  (unwind-protect
       (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
              (initial-ids (mapcar #'apeiron.core:object-id
                                   (apeiron.core:world-all-rooms world))))

         (is (>= (length initial-ids) 2))

         ;; Simulate restart: close store and restore
         (bknr.datastore:close-store)
         ;; characters is a transient slot — auto-initialized on restore

         (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
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
  (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
         (gathering (apeiron.core:starting-room world)))
    ;; The Gathering has 4 connections (north, east, west, south)
    (is (= 4 (length (apeiron.core:room-connections gathering)))
        "Should have exactly 4 connections before restart")
    ;; First restart
    (apeiron.persistence:sync-world)
    (bknr.datastore:close-store)
    (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
           (reloaded (apeiron.core:starting-room new-world)))
      (is (= 4 (length (apeiron.core:room-connections reloaded)))
          "After 1st restart: should have 4 connections, not ~D"
          (length (apeiron.core:room-connections reloaded)))
      ;; Second restart — this often reveals the duplication
      (apeiron.persistence:sync-world)
      (bknr.datastore:close-store)
      (let* ((newer-world (apeiron.persistence:world-restore-or-initialize))
             (reloaded2 (apeiron.core:starting-room newer-world)))
        (is (= 4 (length (apeiron.core:room-connections reloaded2)))
            "After 2nd restart: should have 4 connections, not ~D"
            (length (apeiron.core:room-connections reloaded2)))))))

(test connect-rooms-on-persistent-world-no-duplicate
  "connect-rooms! on a persistent world must not duplicate connections
in the room's connections list."
  (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
         (gathering (apeiron.core:starting-room world))
         (count-before (length (apeiron.core:room-connections gathering)))
         (new-room (apeiron.core:create-object! world (apeiron.core:new-room :name "Secret"))))
    (apeiron.core:connect-rooms! world gathering "west" new-room "east")
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
       (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
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
         (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
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

(test guestbook-present-after-restore
  "After closing and reopening the BKNR store, the guestbook should still
be present in 'The Gathering' room.  This guards against a bug where
CONTAINER-ADD-OBJECT did not set OBJECT-LOCATION, so the rebuild step
in WORLD-RESTORE-OR-INITIALIZE could not find the guestbook and it
disappeared from the room."
  (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
         (tavern (apeiron.core:starting-room world))
         (gathering-name (apeiron.core:object-name tavern)))

    (is (string= "The Gathering" gathering-name))

    ;; Guestbook should be in the room after first materialization
    (let ((gb-first (find-if (lambda (obj) (typep obj 'apeiron.core:mud-guestbook))
                             (apeiron.core:container-all-objects tavern))))
      (is (not (null gb-first))
          "Guestbook should be in The Gathering after first materialization"))

    ;; Sync and restart
    (apeiron.persistence:sync-world)
    (bknr.datastore:close-store)

    (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
           (reloaded-tavern (apeiron.core:starting-room new-world))
           (gb-after (find-if (lambda (obj) (typep obj 'apeiron.core:mud-guestbook))
                              (apeiron.core:container-all-objects reloaded-tavern))))
      (is (not (null gb-after))
          "Guestbook should still be in The Gathering after BKNR restore"))))

(test unbound-persistent-slots-initialized-after-restore
  "When BKNR restores from a snapshot that predates the addition of a
persistent slot, that slot remains UNBOUND after restore (the snapshot
has no value for it and initforms are not applied during restore).
INITIALIZE-TRANSIENT-INSTANCE must reinitialize such slots from their
initforms so they do not cause SLOT-UNBOUND errors on access."
  ;; The user scenario: after restart, connection-find for any direction
  ;; must NOT signal SLOT-UNBOUND.  The default world's connections
  ;; are created without :synonyms-a/:synonyms-b, so the slot is bound
  ;; but nil — this is fine.  The bug only manifests when the slot is
  ;; genuinely UNBOUND (e.g. when a slot was added post-snapshot).
  (let* ((world (apeiron.persistence:world-restore-or-initialize :force-new t))
         (g (starting-room world)))
    ;; Verify connection-find returns a connection for primary directions
    (is (not (null (connection-find g "east"))) "Find east")
    (is (not (null (connection-find g "west"))) "Find west")
    (is (not (null (connection-find g "north"))) "Find north")
    (is (not (null (connection-find g "south"))) "Find south"))
  ;; After a full snapshot/restore cycle
  (apeiron.persistence:sync-world)
  (bknr.datastore:close-store)
  (let* ((world2 (apeiron.persistence:world-restore-or-initialize))
         (g2 (starting-room world2)))
    (is (not (null (connection-find g2 "east"))) "Find east after restore")
    (is (not (null (connection-find g2 "west"))) "Find west after restore")
    (is (not (null (connection-find g2 "north"))) "Find north after restore")
    (is (not (null (connection-find g2 "south"))) "Find south after restore"))
  ;; Simulate a slot added post-snapshot via slot-makunbound, then
  ;; verify that initialize-transient-instance re-initializes it.
  (let* ((world3 (apeiron.persistence:world-restore-or-initialize))
         (g3 (starting-room world3))
         (conn (first (room-connections g3))))
    (slot-makunbound conn 'apeiron.core::synonyms-a)
    (is-false (slot-boundp conn 'apeiron.core::synonyms-a) "unbound after makunbound")
    (bknr.datastore:initialize-transient-instance conn)
    (is-true (slot-boundp conn 'apeiron.core::synonyms-a) "re-bound after init")))

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
