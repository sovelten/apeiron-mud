;;;; telnet/protocol.lisp — RFC 854 Telnet Protocol Specification implementation
;;;;
;;;; Implements the Telnet Protocol as specified in RFC 854 and related RFCs.
;;;; This file contains:
;;;;   - Protocol constants (command bytes, option numbers)
;;;;   - Option negotiation state machine
;;;;   - IAC escape/unescape logic
;;;;
;;;; References:
;;;;   RFC 854  — Telnet Protocol Specification
;;;;   RFC 855  — Telnet Option Specifications
;;;;   RFC 856  — Telnet Binary Transmission
;;;;   RFC 857  — Telnet Echo Option
;;;;   RFC 858  — Telnet Suppress Go Ahead Option
;;;;   RFC 1073 — Telnet Window Size Option (NAWS)
;;;;   RFC 1091 — Telnet Terminal Type Option

(in-package #:telnet)

;;; ----------------------------------------------------------------
;;; Condition types
;;; ----------------------------------------------------------------

(define-condition telnet-error (error)
  ((message :initarg :message :reader telnet-error-message))
  (:report (lambda (c s) (format s "Telnet error: ~A" (telnet-error-message c))))
  (:documentation "Base condition for telnet protocol errors."))

(define-condition telnet-connection-lost (telnet-error)
  ()
  (:report (lambda (c s) (format s "Telnet connection lost: ~A" (telnet-error-message c))))
  (:documentation "Raised when the underlying connection is broken."))

;;; ----------------------------------------------------------------
;;; RFC 854 Command Codes
;;; ----------------------------------------------------------------
;;;
;;; We use DEFVAR rather than DEFCONSTANT because several of these names
;;; (DO, DONT, WILL, WONT, BREAK, SB) conflict with CL symbols.  Shadowing
;;; combined with DEFCONSTANT triggers SBCL package-lock violations even
;;; when the symbols are correctly shadowed.  DEFVAR works correctly with
;;; shadowed symbols and is standard practice for protocol constants that
;;; may need to be redefined during development.

(defvar iac    255 "Interpret As Command — escape to command mode.")
(defvar dont   254 "Deny request to perform option.")
(defvar do     253 "Request that other party perform option.")
(defvar wont   252 "Refuse to perform option.")
(defvar will   251 "Agree/offer to perform option.")
(defvar sb     250 "Subnegotiation begin.")
(defvar se     240 "Subnegotiation end.")
(defvar nop    241 "No Operation (used for keepalive).")
(defvar dm     242 "Data Mark — sync signal in urgent data stream.")
(defvar break  243 "Break — attention signal.")
(defvar ip     244 "Interrupt Process — terminate current process.")
(defvar ao     245 "Abort Output — discard buffered output.")
(defvar ayt    246 "Are You There — query for presence.")
(defvar ec     247 "Erase Character — delete previous character.")
(defvar el     248 "Erase Line — delete current line.")
(defvar ga     249 "Go Ahead — end of half-duplex transmission.")

;;; ----------------------------------------------------------------
;;; Well-Known Telnet Options (RFC numbers)
;;; ----------------------------------------------------------------

(defconstant +telnet-opt-binary+              0 "Binary Transmission (RFC 856).")
(defconstant +telnet-opt-echo+                1 "Echo (RFC 857).")
(defconstant +telnet-opt-suppress-go-ahead+   3 "Suppress Go Ahead (RFC 858).")
(defconstant +telnet-opt-status+              5 "Status (RFC 859).")
(defconstant +telnet-opt-timing-mark+         6 "Timing Mark (RFC 860).")
(defconstant +telnet-opt-terminal-type+      24 "Terminal Type (RFC 1091).")
(defconstant +telnet-opt-naws+               31 "Negotiate About Window Size (RFC 1073).")
(defconstant +telnet-opt-terminal-speed+     32 "Terminal Speed (RFC 1079).")
(defconstant +telnet-opt-new-environ+        39 "New Environment (RFC 1572).")

;;; ----------------------------------------------------------------
;;; Option State
;;; ----------------------------------------------------------------

(defstruct telnet-option-state
  "Tracks the negotiation state for a single telnet option on one side."
  (wanted  nil :type boolean)
  (enabled nil :type boolean)
  (pending nil :type boolean))

;;; ----------------------------------------------------------------
;;; Protocol Engine
;;; ----------------------------------------------------------------

(defclass telnet-protocol ()
  ((local-options
    :initform (make-hash-table :test 'eql)
    :reader telnet-local-options
    :documentation "Hash of option-id -> telnet-option-state for our side.")
   (remote-options
    :initform (make-hash-table :test 'eql)
    :reader telnet-remote-options
    :documentation "Hash of option-id -> telnet-option-state for remote side.")
   (option-handlers
    :initform (make-hash-table :test 'eql)
    :reader telnet-option-handlers
    :documentation "Hash of option-id -> function to call on subnegotiation data.")
   (subneg-buffer
    :initform (make-array 256 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)
    :reader telnet-subneg-buffer
    :documentation "Buffer accumulating subnegotiation bytes.")
   (in-subneg
    :initform nil :type boolean
    :accessor telnet-in-subneg-p
    :documentation "True when we are inside a subnegotiation (SB seen, SE not yet seen).")
   (terminal-type
    :initform "UNKNOWN"
    :accessor telnet-terminal-type
    :documentation "Terminal type reported by client (via TERMINAL-TYPE option).")
   (window-width
    :initform 80 :type (integer 0 65535)
    :accessor telnet-window-width
    :documentation "Client window width in characters (from NAWS).")
   (window-height
    :initform 24 :type (integer 0 65535)
    :accessor telnet-window-height
    :documentation "Client window height in characters (from NAWS)."))
  (:documentation "RFC 854 telnet protocol engine.

Manages option negotiation state and provides methods to process incoming
telnet commands and generate outgoing ones.  This class is pure protocol
logic — it performs no I/O itself."))

;;; ----------------------------------------------------------------
;;; Local / Remote option accessors
;;; ----------------------------------------------------------------

(defun telnet-local-option (protocol option)
  "Return the telnet-option-state for a LOCAL option (what WE do), or NIL."
  (gethash option (telnet-local-options protocol)))

(defun telnet-remote-option (protocol option)
  "Return the telnet-option-state for a REMOTE option (what THEY do), or NIL."
  (gethash option (telnet-remote-options protocol)))

(defun (setf telnet-local-option) (state protocol option)
  (setf (gethash option (telnet-local-options protocol)) state))

(defun (setf telnet-remote-option) (state protocol option)
  (setf (gethash option (telnet-remote-options protocol)) state))

;;; ----------------------------------------------------------------
;;; Option negotiation helpers
;;; ----------------------------------------------------------------

(defun telnet-register-option-handler (protocol option handler-fn)
  "Register HANDLER-FN to be called on subnegotiation data for OPTION.
HANDLER-FN receives (protocol option byte-vector)."
  (setf (gethash option (telnet-option-handlers protocol)) handler-fn))

(defun ensure-option-state (protocol side option)
  "Ensure an option-state exists for the given SIDE (:local or :remote)."
  (let ((table (ecase side
                 (:local  (telnet-local-options protocol))
                 (:remote (telnet-remote-options protocol)))))
    (or (gethash option table)
        (setf (gethash option table)
              (make-telnet-option-state)))))

;;; ----------------------------------------------------------------
;;; Outgoing command builders
;;; ----------------------------------------------------------------

(declaim (inline make-command-2 make-command-1))

(defun make-command-2 (cmd option)
  "Build a 3-byte telnet command: IAC CMD OPTION.
Returns a simple (unsigned-byte 8) vector."
  (let ((v (make-array 3 :element-type '(unsigned-byte 8))))
    (setf (aref v 0) iac
          (aref v 1) cmd
          (aref v 2) option)
    v))

(defun make-command-1 (cmd)
  "Build a 2-byte telnet command: IAC CMD.
Returns a simple (unsigned-byte 8) vector."
  (let ((v (make-array 2 :element-type '(unsigned-byte 8))))
    (setf (aref v 0) iac
          (aref v 1) cmd)
    v))

(defun make-subneg-command (option data)
  "Build a subnegotiation command: IAC SB OPTION DATA... IAC SE."
  (let* ((dlen (length data))
         (v (make-array (+ 5 dlen) :element-type '(unsigned-byte 8))))
    (setf (aref v 0) iac
          (aref v 1) sb
          (aref v 2) option)
    (replace v data :start1 3)
    (setf (aref v (+ 3 dlen)) iac
          (aref v (+ 4 dlen)) se)
    v))

;;; ----------------------------------------------------------------
;;; Incoming command processing
;;; ----------------------------------------------------------------

(defgeneric telnet-process-command (protocol command option)
  (:documentation
   "Process an incoming telnet command (after IAC).
COMMAND is one of WILL/WONT/DO/DONT.
OPTION is the option byte.
Returns a list of byte-vectors that should be written back in response,
or NIL if no response is needed.

Implementation follows the RFC 854 symmetric negotiation model:
- DO/DONT refer to what WE should do (they ask/deny us).
- WILL/WONT refer to what THEY will/won't do (they offer/refuse)."))

(defmethod telnet-process-command ((p telnet-protocol) command option)
  "Default method — silently ignore unrecognized commands per RFC 854."
  (declare (ignore p command option))
  nil)

;; DO — Remote asks us to perform OPTION
(defmethod telnet-process-command ((p telnet-protocol) (command (eql telnet::do)) option)
  (let ((state (ensure-option-state p :local option)))
    (cond
      ;; Already enabled — no response needed (prevents negotiation loops)
      ((telnet-option-state-enabled state)
       nil)
      ;; Wanted but not yet enabled — enable and confirm
      ((telnet-option-state-wanted state)
       (setf (telnet-option-state-enabled state) t
             (telnet-option-state-pending state) nil)
       (list (make-command-2 telnet::will option)))
      ;; Not wanted
      (t
       (list (make-command-2 telnet::wont option))))))

;; DONT — Remote asks us to stop performing OPTION
(defmethod telnet-process-command ((p telnet-protocol) (command (eql telnet::dont)) option)
  (let ((state (ensure-option-state p :local option)))
    ;; Only respond if there's a state change to confirm
    (when (telnet-option-state-enabled state)
      (setf (telnet-option-state-enabled state) nil
            (telnet-option-state-pending state) nil)
      (list (make-command-2 telnet::wont option)))))

;; WILL — Remote offers to perform OPTION
(defmethod telnet-process-command ((p telnet-protocol) (command (eql telnet::will)) option)
  (let ((state (ensure-option-state p :remote option)))
    (cond
      ;; Already enabled — no response needed (prevents negotiation loops)
      ((telnet-option-state-enabled state)
       nil)
      ;; Wanted but not yet enabled — enable and confirm
      ((telnet-option-state-wanted state)
       (setf (telnet-option-state-enabled state) t
             (telnet-option-state-pending state) nil)
       (list (make-command-2 telnet::do option)))
      ;; Not wanted
      (t
       (list (make-command-2 telnet::dont option))))))

;; WONT — Remote refuses to perform OPTION
(defmethod telnet-process-command ((p telnet-protocol) (command (eql telnet::wont)) option)
  (let ((state (ensure-option-state p :remote option)))
    ;; Only respond if there's a state change to confirm
    (when (telnet-option-state-enabled state)
      (setf (telnet-option-state-enabled state) nil
            (telnet-option-state-pending state) nil)
      (list (make-command-2 telnet::dont option)))))

;;; ----------------------------------------------------------------
;;; Subnegotiation processing
;;; ----------------------------------------------------------------

(defgeneric telnet-process-subnegotiation (protocol option data)
  (:documentation
   "Process a completed subnegotiation.
OPTION is the option number.
DATA is a (simple-array (unsigned-byte 8) (*)) of the subnegotiation payload.
Returns a list of byte-vectors that should be written in response, or NIL."))

(defmethod telnet-process-subnegotiation ((p telnet-protocol) option data)
  "Default: delegate to registered handler, if any."
  (let ((handler (gethash option (telnet-option-handlers p))))
    (when handler
      (funcall handler p option data))))

;;; ----------------------------------------------------------------
;;; Built-in option handlers
;;; ----------------------------------------------------------------

;; NAWS (Negotiate About Window Size) — RFC 1073
(defun %handle-naws (protocol option data)
  "Handle NAWS subnegotiation: extract width and height."
  (declare (ignore option))
  (when (>= (length data) 4)
    (let ((width  (+ (ash (aref data 0) 8) (aref data 1)))
          (height (+ (ash (aref data 2) 8) (aref data 3))))
      (setf (telnet-window-width protocol) width
            (telnet-window-height protocol) height)))
  nil)

;; TERMINAL-TYPE — RFC 1091
(defun %handle-terminal-type (protocol option data)
  "Handle TERMINAL-TYPE subnegotiation."
  (declare (ignore option))
  (when (and (>= (length data) 1) (= (aref data 0) 0)) ; IS
    (let ((term (map 'string #'code-char (subseq data 1))))
      (setf (telnet-terminal-type protocol) term)))
  nil)

;;; ----------------------------------------------------------------
;;; Default handler registration
;;; ----------------------------------------------------------------

(defmethod initialize-instance :after ((p telnet-protocol) &key)
  "Register the built-in subnegotiation handlers (NAWS, TERMINAL-TYPE)
on every protocol instance.  This guarantees these options are
interpreted out of the box, independent of whether the application
calls TELNET-INIT-NEGOTIATION."
  (telnet-register-option-handler p +telnet-opt-naws+ #'%handle-naws)
  (telnet-register-option-handler p +telnet-opt-terminal-type+ #'%handle-terminal-type))

;;; ----------------------------------------------------------------
;;; Initial negotiation setup
;;; ----------------------------------------------------------------

(defun telnet-init-negotiation (protocol)
  "Return the initial set of commands to send when a connection is established.

We request:
  - DO Suppress Go Ahead    (we don't use half-duplex)
  - WILL Suppress Go Ahead  (we don't send GA)
  - WILL Echo               (we handle character echo on the server side)
  - DO NAWS                 (we want to know window dimensions)
  - DO Terminal Type        (we want to know the terminal type)

The commands are a list of byte-vectors ready to be written to the socket."
  ;; Built-in subnegotiation handlers (NAWS, TERMINAL-TYPE) are registered
  ;; automatically by INITIALIZE-INSTANCE on the protocol object.

  ;; Mark options we want
  ;; Local: we WILL do these
  (let ((local-echo (ensure-option-state protocol :local +telnet-opt-echo+))
        (local-sga  (ensure-option-state protocol :local +telnet-opt-suppress-go-ahead+)))
    (setf (telnet-option-state-wanted local-echo) t
          (telnet-option-state-pending local-echo) t
          (telnet-option-state-wanted local-sga) t
          (telnet-option-state-pending local-sga) t))

  ;; Remote: we DO want these from the client
  (let ((remote-naws (ensure-option-state protocol :remote +telnet-opt-naws+))
        (remote-term (ensure-option-state protocol :remote +telnet-opt-terminal-type+))
        (remote-sga  (ensure-option-state protocol :remote +telnet-opt-suppress-go-ahead+)))
    (setf (telnet-option-state-wanted remote-sga) t
          (telnet-option-state-pending remote-sga) t
          (telnet-option-state-wanted remote-naws) t
          (telnet-option-state-pending remote-naws) t
          (telnet-option-state-wanted remote-term) t
          (telnet-option-state-pending remote-term) t))

  ;; Build initial command list
  (list (make-command-2 do +telnet-opt-suppress-go-ahead+)
        (make-command-2 will +telnet-opt-suppress-go-ahead+)
        (make-command-2 will +telnet-opt-echo+)
        (make-command-2 do +telnet-opt-naws+)
        (make-command-2 do +telnet-opt-terminal-type+)))

;;; ----------------------------------------------------------------
;;; IAC Escaping
;;; ----------------------------------------------------------------

(declaim (inline iac-escape-length))

(defun iac-escape-length (byte-array)
  "Return the number of bytes BYTE-ARRAY would take after IAC-escaping.
Each IAC byte (255) must be doubled."
  (let ((len (length byte-array)))
    (loop for b across byte-array
          when (= b iac) do (incf len))
    len))

(defun iac-escape (byte-array)
  "Return a new byte-array with all IAC bytes doubled (IAC -> IAC IAC)."
  (let* ((src-len (length byte-array))
         (dst-len (iac-escape-length byte-array))
         (result (make-array dst-len :element-type '(unsigned-byte 8)))
         (j 0))
    (loop for i below src-len do
      (let ((b (aref byte-array i)))
        (setf (aref result j) b)
        (incf j)
        (when (= b iac)
          (setf (aref result j) iac)
          (incf j))))
    result))
