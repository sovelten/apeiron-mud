(in-package :mud)

(defclass name-mixin ()
    ((name :initarg :name
           :accessor name)))

(defclass number-mixin ()
    ((number :initarg :number
           :accessor get-number)))

(defclass sephiroth (name-mixin number-mixin)
  ())

(defclass path (name-mixin number-mixin)
  ((letter :initarg :letter
           :accessor path-letter)
   (key :initarg :key
        :accessor path-key)
   (from :initarg :from
         :accessor path-from)
   (to :initarg :to
         :accessor path-to)))

(defun sephiroth-room (sephiroth)
  (new-room :name (name sephiroth)
            :description (write-to-string (get-number sephiroth))))

(defvar keter (make-instance 'sephiroth :name "Keter" :number 1))
(defvar chokmah (make-instance 'sephiroth :name "Chokmah" :number 2))
(defvar binah (make-instance 'sephiroth :name "Binah" :number 3))
(defvar chesed (make-instance 'sephiroth :name "Chesed" :number 4))
(defvar geburah (make-instance 'sephiroth :name "Geburah" :number 5))
(defvar tiphareth (make-instance 'sephiroth :name "Tiphareth" :number 6))
(defvar netzach (make-instance 'sephiroth :name "Netzach" :number 7))
(defvar hod (make-instance 'sephiroth :name "Hod" :number 8))
(defvar yesod (make-instance 'sephiroth :name "Yesod" :number 9))
(defvar malkuth (make-instance 'sephiroth :name "Malkuth" :number 10))

(defvar paths
  (list (make-instance 'path
                       :name "The Magician"
                       :number 1
                       :key 1
                       :letter "Beth"
                       :from keter
                       :to binah)
        (make-instance 'path
                       :name "The Fool"
                       :number 11
                       :key 0
                       :letter "Aleph"
                       :from keter
                       :to chokmah)
        (make-instance 'path
                       :name "The High Priestess"
                       :number 13
                       :key 2
                       :letter "Gimel"
                       :from keter
                       :to tiphareth)
        (make-instance 'path
                       :name "The Empress"
                       :number 14
                       :key 3
                       :letter "Daleth"
                       :from chokmah
                       :to binah)))

(defun paths-from (sephiroth)
  (loop for path in paths
        when (equal (path-from path) sephiroth)
          collect path))

(defun tree-of-life ()
  (let ((world (make-instance 'new-world))
        (keter-room (sephiroth-room keter))
        (chokmah-room (sephiroth-room chokmah))
        (binah-room (sephiroth-room binah))
        (chesed-room (sephiroth-room chesed))
        (geburah-room (sephiroth-room geburah))
        (tiphareth-room (sephiroth-room tiphareth))
        (netzach-room (sephiroth-room netzach))
        (hod-room (sephiroth-room hod))
        (yesod-room (sephiroth-room yesod))
        (malkuth-room (sephiroth-room malkuth)))
    (world-set-object-id! world keter-room)
    (world-set-object-id! world chokmah-room)
    (world-set-object-id! world binah-room)
    (world-set-object-id! world chesed-room)
    (world-set-object-id! world geburah-room)
    (world-set-object-id! world tiphareth-room)
    (world-set-object-id! world netzach-room)
    (world-set-object-id! world hod-room)
    (world-set-object-id! world yesod-room)
    (world-set-object-id! world malkuth-room)))
