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
         ;; players is a transient slot — auto-initialized on restore

         (let* ((new-world (apeiron.persistence:world-restore-or-initialize))
                (restored-ids (mapcar #'apeiron.core:object-id
                                      (apeiron.core:world-all-rooms new-world))))
           ;; Ensure rooms were loaded with their original world-level IDs
           (is (= (length initial-ids) (length restored-ids)))
           (is (subsetp initial-ids restored-ids))
           ;; Add a new room post-restart
           (let ((new-room (apeiron.core:new-room :name "Post-Restart Room")))
             (apeiron.core:world-set-object-id! new-world new-room)
             (let ((new-id (apeiron.core:object-id new-room)))
               (is (not (member new-id restored-ids))
                   "New object ID ~D conflicts with existing loaded room IDs: ~A"
                   new-id restored-ids))))))

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
         ;; players is a transient slot — auto-initialized on restore
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

(test guestbook-present-after-restore
  "After closing and reopening the BKNR store, the guestbook should still
be present in 'The Gathering' room.  This guards against a bug where
CONTAINER-ADD-OBJECT did not set OBJECT-LOCATION, so the rebuild step
in WORLD-RESTORE-OR-INITIALIZE could not find the guestbook and it
disappeared from the room."
  ;; Clean up any leftover CSV from earlier runs
  (let ((csv-path (merge-pathnames "guestbook.csv" *data-directory*)))
    (when (probe-file csv-path)
      (delete-file csv-path)))
  (unwind-protect
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
               "Guestbook should still be in The Gathering after BKNR restore")))
    ;; Clean up CSV file after test
    (let ((csv-path (merge-pathnames "guestbook.csv" *data-directory*)))
      (when (probe-file csv-path)
        (ignore-errors (delete-file csv-path))))))
