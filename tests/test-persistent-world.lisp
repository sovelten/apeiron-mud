(in-package #:mud-test)

(in-suite mud-tests)

(test world-initialization
  "Test that the world initializes properly"
  (let ((world (mud:world-restore-or-initialize)))
    (is (not (null (mud:get-config-key world :starting-room-id))))
    (is (> (mud:total-rooms) 0))))

(test bknr-id-conflict-on-restart
  "Test that world-level IDs do NOT conflict after store close/reopen."
  (unwind-protect
       (let* ((world (mud:world-restore-or-initialize :force-new t))
              (initial-ids (mapcar #'mud:object-id (mud:rooms))))

         (is (>= (length initial-ids) 2))

         ;; Simulate restart: close store and restore
         (bknr.datastore:close-store)
         ;; players is a transient slot — auto-initialized on restore

         (let* ((new-world (mud:world-restore-or-initialize))
                (restored-ids (mapcar #'mud:object-id (mud:rooms))))
           ;; Ensure rooms were loaded with their original world-level IDs
           (is (= (length initial-ids) (length restored-ids)))
           (is (subsetp initial-ids restored-ids))
           ;; Add a new room post-restart
           (let ((new-room (mud:new-room :name "Post-Restart Room")))
             (mud:world-set-object-id! new-world new-room)
             (let ((new-id (mud:object-id new-room)))
               (is (not (member new-id restored-ids))
                   "New object ID ~D conflicts with existing loaded room IDs: ~A"
                   new-id restored-ids)))))))

(test guestbook-persistence
  "Test that guestbook entries survive store close/reopen via CSV persistence."
  (unwind-protect
       ;; Find the guestbook in the starting room
       (let* ((world (mud:world-restore-or-initialize :force-new t))
              (tavern (mud:starting-room world))
              (guestbook (find-if (lambda (obj) (typep obj 'mud:mud-guestbook))
                                  (mud:room-contents tavern))))

         (is (not (null guestbook)))

         ;; Add an entry (writes to CSV on disk)
         (mud:guestbook-add-entry guestbook "Sophia" "Persistent via CSV!")

         ;; Snapshot
         (mud:sync-world)

         ;; Simulate restart
         (bknr.datastore:close-store)
         ;; players is a transient slot — auto-initialized on restore
         ;; Find the guestbook in the restored world
         (let* ((new-world (mud:world-restore-or-initialize))
                (reloaded-tavern (mud:starting-room new-world))
                (reloaded-gbook (find-if (lambda (obj) (typep obj 'mud:mud-guestbook))
                                         (mud:room-contents reloaded-tavern))))
           (is (not (null reloaded-gbook)))
           (let ((entries (mud:guestbook-entries reloaded-gbook)))
             (is (= (length entries) 1))
             (is (equal (getf (first entries) :author) "Sophia"))
             (is (equal (getf (first entries) :message) "Persistent via CSV!")))))))
