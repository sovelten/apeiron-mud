;;;; src/verbs/serialize.lisp — the registry as plain, persistable data
;;;;
;;;; A registry is immutable FSET maps of definitions, so it can be turned
;;;; into an FSET map of *plain data* — strings, numbers, lists, keywords —
;;;; with no class instances.  That form is what a datastore (e.g. a
;;;; MUD-WORLD CONFIG slot) can hold directly: the code is stored as printed
;;;; source text.  MAP->VERB-REGISTRY rebuilds the registry without
;;;; re-hashing, preserving the CIDs exactly (they are the keys).

(in-package #:apeiron.verbs)

(defparameter *verb-registry-format* 1
  "Serialization format version embedded in the map produced by
VERB-REGISTRY->MAP.")

(defun print-form (form)
  "Printed, readable representation of FORM."
  (let ((*print-readably* t)
        (*print-circle* nil))
    (prin1-to-string form)))

(defun read-form (string)
  "Read back a form printed by PRINT-FORM.  Reader evaluation is disabled:
serialized verbs are data, never evaluated in this path."
  (let ((*read-eval* nil))
    (read-from-string string)))

(defun serialize-verb-definition (definition)
  "Return DEFINITION as an FSET map of plain data."
  (let ((map (fset:empty-map)))
    (flet ((put (key value) (setf map (fset:with map key value))))
      (put :cid (verb-definition-cid definition))
      (put :name (print-form (verb-definition-name definition)))
      (put :lambda-list (print-form (verb-definition-lambda-list definition)))
      (put :body (print-form (verb-definition-body definition)))
      (put :docstring (verb-definition-docstring definition))
      (put :references
           (mapcar (lambda (pair) (cons (print-form (car pair)) (cdr pair)))
                   (verb-definition-references definition)))
      (put :unresolved
           (mapcar #'print-form (verb-definition-unresolved-references definition))))
    map))

(defun verb-registry->map (registry)
  "Return REGISTRY as an immutable FSET map of plain data.

The map has keys :VERB-REGISTRY-FORMAT, :DEFINITIONS (a list of serialized
definitions), :NAMES (a list of (printed-name . cid)) and :HISTORY (a list
of (printed-name . cid-list)).  It contains no class instances and no
symbols, so it can be persisted directly; MAP->VERB-REGISTRY restores it."
  (let ((definitions '())
        (names '())
        (history '()))
    (fset:do-map (cid definition (registry-definitions registry))
      (declare (ignore cid))
      (push (serialize-verb-definition definition) definitions))
    (fset:do-map (name cid (registry-names registry))
      (push (cons (print-form name) cid) names))
    (fset:do-map (name cids (registry-history registry))
      (push (cons (print-form name) cids) history))
    (let ((map (fset:empty-map)))
      (flet ((put (key value) (setf map (fset:with map key value))))
        (put :verb-registry-format *verb-registry-format*)
        (put :definitions (nreverse definitions))
        (put :names (nreverse names))
        (put :history (nreverse history)))
      map)))

(defun map->verb-registry (map)
  "Rebuild a verb registry from the plain data MAP produced by
VERB-REGISTRY->MAP.  CIDs, names and history are restored verbatim, so the
result addresses exactly the same definitions."
  (let ((registry (make-verb-registry)))
    (dolist (serialized (fset:lookup map :definitions))
      (let* ((cid (fset:lookup serialized :cid))
             (name (read-form (fset:lookup serialized :name)))
             (lambda-list (read-form (fset:lookup serialized :lambda-list)))
             (body (read-form (fset:lookup serialized :body)))
             (docstring (fset:lookup serialized :docstring))
             (references (mapcar (lambda (pair)
                                   (cons (read-form (car pair)) (cdr pair)))
                                 (fset:lookup serialized :references)))
             (unresolved (mapcar #'read-form
                                 (fset:lookup serialized :unresolved))))
        (setf (registry-definitions registry)
              (fset:with (registry-definitions registry)
                         cid
                         (make-instance 'verb-definition
                                        :cid cid
                                        :name name
                                        :lambda-list lambda-list
                                        :body body
                                        :source `(lambda ,lambda-list ,@body)
                                        :docstring docstring
                                        :references references
                                        :unresolved-references unresolved
                                        :created-at 0)))))
    (dolist (pair (fset:lookup map :names))
      (setf (registry-names registry)
            (fset:with (registry-names registry) (read-form (car pair)) (cdr pair))))
    (dolist (pair (fset:lookup map :history))
      (setf (registry-history registry)
            (fset:with (registry-history registry) (read-form (car pair)) (cdr pair))))
    registry))
