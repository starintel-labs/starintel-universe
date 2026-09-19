% Discovered starintel-server contracts (verified against 4721efaf).
contract(target_submission, 'POST /new/target/:actor needs _id, dataset, dtype=target, data.target, delay 1..31536000').
contract(dispatch_envelope, 'local actors receive the target-dispatch-envelope CLOS object; read fields via star.actors:target-record-* accessors').
contract(actor_registration, 'register in ONE self-reporting function on starintel-gserver:*actors-start-hook*; per-actor hooks abort the chain silently on error').
contract(actor_constructor, 'sento.actor-context:actor-of (ac: nickname); plain sento: and sento.actor: lack actor-of').
contract(result_documents, 'ingest validates v0.9 strictly: closed data per dtype; arbitrary actor results map onto observation{observer_id,value,observation_type,method,instrument}').
contract(json_construction, 'jsown:new-js does not evaluate value positions; build objects with (setf (jsown:val o k) v)').
contract(baked_defparameters, 'save-lisp-and-die images bake defparameter env reads; rebind runtime settings from the init file (runs before DB/Rabbit/HTTP start)').
contract(replay_semantics, 'server assigns document _ids at ingest; replay equality is over (dtype,dataset,data) content; replayed targets re-execute (at-least-once)').
contract(dev_bypass, 'STAR_AUTH_MODE=disabled needs star:*auth-dev-bypass* t set from the init file plus pepper/initial-password values').
