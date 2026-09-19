;;;; StarIntel Universe — deterministic test actors.
;;;; Loaded through the star-server init file (`star-server start -i ...`)
;;;; via tests/actors/lib/test-init.lisp.
;;;; These actors use the REAL actor protocol (actor-index registration on
;;;; *actors-start-hook*) and publish results through the REAL RabbitMQ
;;;; producer as canonical v0.9 `observation` documents, so results enter
;;;; StarIntel exactly like production actors.
;;;; No LLM, no network beyond the service boundaries, fully deterministic.
;;;; Result field mapping (observation schema, closed data):
;;;;   observer_id      = actor name
;;;;   value            = primary payload (target string)
;;;;   observation_type = "universe-test"
;;;;   method           = actor-specific kind
;;;;   instrument       = actor-specific detail (always a string)

(in-package :star)

(defpackage :starintel-test-actors
  (:use :cl))

(in-package :starintel-test-actors)

(defvar *state* (make-hash-table :test #'equal)
  "Shared deterministic state for stateful test actors (counters, digests).")

(defvar *echo-actor* nil)
(defvar *transform-actor* nil)
(defvar *slow-actor* nil)
(defvar *streaming-actor* nil)
(defvar *crash-actor* nil)
(defvar *retry-actor* nil)
(defvar *invalid-result-actor* nil)
(defvar *producer-actor* nil)
(defvar *consumer-actor* nil)
(defvar *lease-race-actor* nil)
(defvar *config-reload-actor* nil)

(defun jobj (&rest kvs)
  "Build a JSOWN object with EVALUATED key/value pairs."
  (let ((o (jsown:empty-object)))
    (loop for (k v) on kvs by #'cddr
          do (setf (jsown:val o k) v))
    o))

(defun emit-observation (actor value method instrument)
  "Publish one canonical v0.9 observation document through the real producer."
  (let ((doc (jobj
              "_id" (cms-ulid:ulid)
              "dtype" "observation"
              "dataset" "starintel-universe-test"
              "schema_version" "0.9.0"
              "version" 1
              "date_added" (star.documents:utc-now)
              "date_updated" (star.documents:utc-now)
              "sources" #()
              "evidence" #()
              "data" (jobj
                      "observer_id" actor
                      "value" value
                      "observation_type" "universe-test"
                      "method" method
                      "instrument" instrument))))
    (star.actors:publish star.actors:*producer-agent*
                         :body (jsown:to-json doc)
                         :routing-key "documents.ingest.observation")))

(defun emit-bad (payload routing-key)
  "Publish an intentionally invalid payload (malformed-document tests)."
  (star.actors:publish star.actors:*producer-agent*
                       :body payload
                       :routing-key routing-key))

;;;; The actor receives the target-dispatch-envelope (CLOS). Access its
;;;; record through the exported accessors; fall back to raw JSON for
;;;; compatibility-path deliveries.
(defun msg-target (msg)
  (or (ignore-errors
        (star.actors:target-record-target
         (star.actors:target-dispatch-envelope-record msg)))
      (ignore-errors (jsown:val-safe msg "target"))
      ""))

(defun msg-options (msg)
  (or (ignore-errors
        (coerce (star.actors:target-record-options
                 (star.actors:target-dispatch-envelope-record msg))
                'list))
      (ignore-errors (jsown:val-safe msg "options"))
      nil))

(defun first-option-value (msg key default)
  (let ((opts (msg-options msg)))
    (if (and opts (listp opts) (jsown:keyp (car opts) key))
        (jsown:val (car opts) key)
        default)))

;;;; echo-actor: returns exactly what it was given.
(defun echo-handler (msg)
  (emit-observation "echo-actor" (msg-target msg) "echo" ""))

;;;; transform-actor: applies a deterministic transform from options.
(defun apply-transform (target op)
  (cond
    ((string= op "uppercase") (string-upcase target))
    ((string= op "reverse") (reverse target))
    (t target)))

(defun transform-handler (msg)
  (let* ((target (msg-target msg))
         (ops (remove nil
                      (mapcar (lambda (o) (ignore-errors (jsown:val-safe o "op")))
                              (msg-options msg))))
         (result (reduce (lambda (acc op) (apply-transform acc op))
                         ops :initial-value target)))
    (emit-observation "transform-actor" target "transform"
                      (format nil "~{~a~^,~}" ops))
    (emit-observation "transform-actor" result "transform-result"
                      (format nil "~{~a~^,~}" ops))))

;;;; slow-actor: sleeps `seconds` (default 2, capped 10) before echoing.
(defun slow-handler (msg)
  (let ((secs (min 10 (max 0 (first-option-value msg "seconds" 2)))))
    (sleep secs)
    (emit-observation "slow-actor" (msg-target msg) "slow"
                      (format nil "~d" secs))))

;;;; streaming-actor: emits `count` progress documents then a final result.
(defun stream-count (msg)
  (min 10 (max 1 (first-option-value msg "count" 3))))

(defun streaming-handler (msg)
  (let ((count (stream-count msg))
        (target (msg-target msg)))
    (loop for i from 1 to count
          do (emit-observation "streaming-actor" target "progress"
                               (format nil "~d/~d" i count)))
    (emit-observation "streaming-actor" target "final"
                      (format nil "~d" count))))

;;;; crash-actor: signals an error immediately; must NEVER yield a result.
(defun crash-handler (msg)
  (declare (ignore msg))
  (error "crash-actor: intentional deterministic failure"))

;;;; retry-actor: fails the first N attempts per target (re-delivering
;;;; the envelope to itself), then succeeds. Exercises real in-system
;;;; retry behavior with deterministic eventual success. Local actor
;;;; errors do not redeliver (fire-and-forget tell), so the actor owns
;;;; its bounded retry loop.
(defun retry-handler (msg)
  (let* ((target (msg-target msg))
         (need (min 5 (max 1 (first-option-value msg "attempts" 2))))
         (key (format nil "retry-~a" target))
         (n (incf (gethash key *state* 0))))
    (if (>= n need)
        (emit-observation "retry-actor" target "retry-success"
                          (format nil "~d" n))
        (progn
          (log:info "retry-actor: attempt ~d of ~d for ~a (retrying)"
                    n need target)
          (bt:make-thread
           (lambda ()
             (sleep 1)
             (ignore-errors
               (star.actors::tell *retry-actor* msg))))))))

;;;; invalid-result-actor: publishes a malformed payload that must be
;;;; rejected by ingest validation and never persisted.
(defun invalid-result-handler (msg)
  (emit-bad "{\"not\":\"a\",\"valid\":\"payload\"}"
            "documents.ingest.testinvalid")
  (emit-observation "invalid-result-actor" (msg-target msg) "invalid-ack" "1"))

;;;; producer-actor: produces a deterministic sequence of documents.
(defun producer-handler (msg)
  (let ((count (stream-count msg))
        (target (msg-target msg)))
    (loop for i from 1 to count
          do (emit-observation "producer-actor" target "produce"
                               (format nil "~d" i)))))

;;;; consumer-actor: consumes its own target stream durably; the digest
;;;; (delivery count) is republished on every message.
(defun consumer-handler (msg)
  (let* ((target (msg-target msg))
         (n (incf (gethash "consumer-deliveries" *state* 0))))
    (emit-observation "consumer-actor" target "consume"
                      (format nil "~d" n))))

;;;; lease-race-actor: records the delivery generation for identical
;;;; concurrent targets (single-flight acceptance evidence).
(defun lease-race-handler (msg)
  (let* ((target (msg-target msg))
         (key (format nil "race-~a" target))
         (delivery (incf (gethash key *state* 0))))
    (emit-observation "lease-race-actor" target "race"
                      (format nil "~d" delivery))))

;;;; config-reload-actor: reflects the CURRENT value of a config file on
;;;; every message (configuration updates take effect without restart).
(defun read-test-config ()
  (let ((path (or (uiop:getenv "STARINTEL_TEST_ACTOR_CONFIG")
                  "/tmp/starintel-test-actor-config"))
        (table (make-hash-table :test #'equal)))
    (with-open-file (s path :if-does-not-exist nil)
      (when s
        (loop for line = (read-line s nil nil)
              while line
              when (position #\= line)
              do (setf (gethash (string-trim " " (subseq line 0 (position #\= line)))
                                table)
                       (string-trim " " (subseq line (1+ (position #\= line))))))))
    table))

(defun config-reload-handler (msg)
  (let ((mode (or (gethash "mode" (read-test-config)) "default")))
    (emit-observation "config-reload-actor" (msg-target msg) "config" mode)))

;;;; ----------------------------------------------------------------
;;;; Registration: real protocol, explicit and self-reporting.
;;;; ----------------------------------------------------------------
(defun make-test-actor (system name handler)
  (let ((actor (sento.actor-context:actor-of system
                                             :name (format nil "test-~a" name)
                                             :receive handler)))
    (star.actors:register-actor name actor)
    actor))

(defun start-universe-test-actors ()
  (let ((system star.actors:*sys*))
    (handler-case
        (progn
          (setf *echo-actor*           (make-test-actor system "echo-actor"           #'echo-handler))
          (setf *transform-actor*      (make-test-actor system "transform-actor"      #'transform-handler))
          (setf *slow-actor*           (make-test-actor system "slow-actor"           #'slow-handler))
          (setf *streaming-actor*      (make-test-actor system "streaming-actor"      #'streaming-handler))
          (setf *crash-actor*          (make-test-actor system "crash-actor"          #'crash-handler))
          (setf *retry-actor*          (make-test-actor system "retry-actor"          #'retry-handler))
          (setf *invalid-result-actor* (make-test-actor system "invalid-result-actor" #'invalid-result-handler))
          (setf *producer-actor*       (make-test-actor system "producer-actor"       #'producer-handler))
          (setf *consumer-actor*       (make-test-actor system "consumer-actor"       #'consumer-handler))
          (setf *lease-race-actor*     (make-test-actor system "lease-race-actor"     #'lease-race-handler))
          (setf *config-reload-actor*  (make-test-actor system "config-reload-actor"  #'config-reload-handler))
          (log:info "StarIntel universe test actors registered (11 deterministic actors)"))
      (error (e)
        (log:error "Universe test actors FAILED to start: ~a" e)
        (error e)))))

(nhooks:add-hook
 starintel-gserver:*actors-start-hook*
 #'start-universe-test-actors)
