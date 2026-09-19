;;;; Universe test init file — rebinds runtime settings from the
;;;; environment (the saved image bakes defparameter defaults at build
;;;; time; this file runs before databases/Rabbit/HTTP start), then
;;;; loads the deterministic test actors.
;;;; NOTE: no DEFUNs here — the init file is evaluated more than once by
;;;; the loader in some startup paths and redefinition is fatal in the
;;;; saved image.

(in-package :star)

(setf star:*couchdb-host* (or (uiop:getenv "COUCHDB_HOST") "127.0.0.1")
      star:*couchdb-port* (let ((v (uiop:getenv "COUCHDB_PORT")))
                            (if (and v (plusp (length v)))
                                (parse-integer v :junk-allowed t)
                                5984))
      star:*couchdb-user* (or (uiop:getenv "COUCHDB_USER") "admin")
      star:*couchdb-password* (or (uiop:getenv "COUCHDB_PASSWORD") "starintel-test")
      star:*couchdb-default-database* (or (uiop:getenv "COUCHDB_DATABASE") "starintel"))

(setf star:*rabbit-address* (or (uiop:getenv "RABBITMQ_ADDRESS") "127.0.0.1")
      star:*rabbit-port* (let ((v (uiop:getenv "RABBITMQ_PORT")))
                           (if (and v (plusp (length v)))
                               (parse-integer v :junk-allowed t)
                               5672))
      star:*rabbit-user* (or (uiop:getenv "RABBITMQ_USER") "guest")
      star:*rabbit-password* (or (uiop:getenv "RABBITMQ_PASSWORD") "guest"))

(setf star:*http-api-address* (or (uiop:getenv "HTTP_API_LISTEN_ADDRESS") "127.0.0.1")
      star:*http-api-port* (let ((v (uiop:getenv "HTTP_API_PORT")))
                             (if (and v (plusp (length v)))
                                 (parse-integer v :junk-allowed t)
                                 15000)))

(setf star:*auth-mode* (or (uiop:getenv "STAR_AUTH_MODE") "disabled"))
;; The disposable test stack binds loopback only; allow the development
;; bypass so tests need no credentials. NEVER use this in production.
(when (string= star:*auth-mode* "disabled")
  (setf star:*auth-dev-bypass* t))
;; Throwaway values for the auth bootstrap (never real secrets).
(setf star:*auth-pepper* (or (uiop:getenv "STAR_AUTH_PEPPER")
                             "starintel-universe-test-pepper")
      star:*auth-initial-password* (or (uiop:getenv "STAR_AUTH_INITIAL_PASSWORD")
                                       "starintel-test"))

(load (or (uiop:getenv "STARINTEL_TEST_ACTORS")
          "tests/actors/lib/starintel-test-actors.lisp"))
