(defpackage #:apeiron-test
  (:use #:cl #:fiveam
        #:apeiron.core
        #:apeiron.core.utils
        #:apeiron.persistence
        #:apeiron.server)
  (:export #:run-tests #:apeiron-tests
           #:core-suite
           #:telnet-suite
           #:persistence-suite
           #:worlds-suite
           #:server-suite
           #:events-suite
           #:setup-test-environment
           #:teardown-test-environment))

(in-package #:apeiron-test)

(def-suite apeiron-tests
    :description "All Apeiron MUD tests")

(def-suite core-suite
    :in apeiron-tests
    :description "Core module tests — objects, rooms, guestbook, characters, world, commands")

(def-suite telnet-suite
    :in apeiron-tests
    :description "Telnet protocol tests")

(def-suite persistence-suite
    :in apeiron-tests
    :description "Persistence module tests — BKNR datastore, world restore")

(def-suite worlds-suite
    :in apeiron-tests
    :description "World module tests — pre-built world areas, NPCs, combat")

(def-suite server-suite
    :in apeiron-tests
    :description "Server module tests — network, integration")

(def-suite events-suite
    :in apeiron-tests
    :description "Event system tests — event types, logging, handlers")

(eval-when (:load-toplevel :execute)
  (setf *debug-mode* nil)
  (setf *colorize* nil)
  (setf *run-mode* :test)
  (setf bknr.datastore::*store-verbose* nil)
  ;; Silence log4cl during testing.  Individual logging tests call
  ;; configure-logging to set up their own per-test file appenders.
  (log:config :fatal :sane :filter :fatal :immediate-flush)
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (ensure-directories-exist temp-dir)
    (ensure-directories-exist data-dir)
    (setf *store-directory* temp-dir)
    (setf *data-directory* data-dir)))

(defun setup-test-environment ()
  "Set up a clean, isolated temporary BKNR store for test runs."
  (setf *debug-mode* nil)
  (setf *colorize* nil)
  (setf bknr.datastore::*store-verbose* nil)
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    (when (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
      (ignore-errors (bknr.datastore:close-store))
      (makunbound 'bknr.datastore:*store*))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (ensure-directories-exist temp-dir)
    (ensure-directories-exist data-dir)
    (setf *store-directory* temp-dir)
    (setf *data-directory* data-dir)
    (format t "~&Test store directory: ~A~%" temp-dir)
    (format t "~&Test data directory: ~A~%" data-dir)))

(defun teardown-test-environment ()
  "Clean up temporary test directories and close any open store."
  (let ((temp-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-bknr/"))
        (data-dir (uiop:subpathname (uiop:default-temporary-directory) "mud-test-data/")))
    (when (and (boundp 'bknr.datastore:*store*)
               bknr.datastore:*store*)
      (ignore-errors (bknr.datastore:close-store))
      (makunbound 'bknr.datastore:*store*))
    (uiop:delete-directory-tree temp-dir :validate (constantly t) :if-does-not-exist :ignore)
    (uiop:delete-directory-tree data-dir :validate (constantly t) :if-does-not-exist :ignore)
    (setf *debug-mode* nil)
    (setf bknr.datastore::*store-verbose* nil)))

(defun test-world-with-rooms ()
  "Create a transient world with rooms, connections, and a guestbook
for tests that need them.  This lets tests avoid depending on the
specific default-transient-world layout."
  (let ((world (make-instance 'mud-world)))
    (let ((tavern (new-room :name "Test Tavern"))
          (forest (new-room :name "Dark Forest"))
          (guestbook (new-guestbook :name "a test guestbook")))
      ;; Register rooms in world
      (world-add-object! world tavern)
      (world-add-object! world forest)
      (world-add-object! world guestbook)
      (container-add-object tavern guestbook)
      ;; Connect rooms (creates a north/south pair)
      (connect-north-south! world forest tavern)
      (world-set-starting-room! world tavern))
    world))

(defun test-world-with-biomes ()
  "Create a transient world with a central hub room connected to four
biome rooms (north, south, east, west) and a guestbook.  Useful for
tests that need directional connections on the starting room."
  (let ((world (make-instance 'mud-world)))
    (let ((hub (new-room :name "Central Hub"))
          (north (new-room :name "Northern Reaches"))
          (south (new-room :name "Southern Swamp"))
          (east (new-room :name "Eastern Desert"))
          (west (new-room :name "Western Woods"))
          (guestbook (new-guestbook :name "a test guestbook")))
      ;; Register rooms in world
      (world-add-object! world hub)
      (world-add-object! world north)
      (world-add-object! world south)
      (world-add-object! world east)
      (world-add-object! world west)
      (world-add-object! world guestbook)
      (container-add-object hub guestbook)
      ;; Connect hub to biomes
      (connect-north-south! world north hub)
      (connect-north-south! world hub south)
      (connect-west-east! world west hub)
      (connect-west-east! world hub east)
      (world-set-starting-room! world hub))
    world))

(defun test-world-with-area ()
  "Create a transient world containing one area: a three-room chain where
the last hop (hall -> treasure) is one-way.  The area, its rooms and its
connections are registered via WORLD-ADD-AREA!."
  (let ((world (make-instance 'mud-world)))
    (let ((area (new-area :name "Test Cavern")))
      (let ((entrance (new-room :name "Cavern Entrance"))
            (hall (new-room :name "Great Hall"))
            (treasure (new-room :name "Treasure Vault")))
        (area-connect-rooms! area entrance hall :to "north" :from "south")
        (area-connect-rooms! area hall treasure
                             :to "east" :from "west"
                             :one-way :a-to-b
                             :one-way-message "The vault door slams shut behind you.")
        (world-add-area! world area)
        (world-set-starting-room! world entrance)))
    world))

(defun run-tests ()
  "Run all MUD tests with a clean, isolated temporary BKNR store."
  (setup-test-environment)
  (unwind-protect
       (let ((*trace-output* (make-broadcast-stream))
             (results (run 'apeiron-tests)))
         (let* ((fiveam-pkg (find-package :fiveam))
                (passed-class (and fiveam-pkg
                                   (find-class (find-symbol "TEST-PASSED" fiveam-pkg) nil)))
                (failed-class (and fiveam-pkg
                                   (find-class (find-symbol "TEST-FAILURE" fiveam-pkg) nil)))
                (skipped-class (and fiveam-pkg
                                    (find-class (find-symbol "TEST-SKIPPED" fiveam-pkg) nil)))
                (passed 0) (failed 0) (pending 0))
           (dolist (r results)
             (cond
               ((and passed-class (typep r passed-class)) (incf passed))
               ((and failed-class (typep r failed-class)) (incf failed))
               ((and skipped-class (typep r skipped-class)) (incf pending))
               (t (incf passed))))
           (format t "~%=== Results: ~D passed, ~D failed, ~D pending ===~%"
                   passed failed pending)
           (when (plusp failed)
             (error "~D test~:P failed" failed))
           (values passed failed pending)))
    (teardown-test-environment)))
