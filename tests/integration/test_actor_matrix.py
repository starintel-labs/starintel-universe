#!/usr/bin/env python3
"""StarIntel Universe — deterministic actor matrix test.

Runs against the disposable full-stack environment booted by up.sh:
CouchDB + RabbitMQ + Valkey + star-server with 11 deterministic actors.

Every assertion is deterministic: fixed targets, fixed options, fixed
expected outcomes. No LLM is involved at any point.

Actor results are canonical v0.9 `observation` documents:
  data.observer_id = actor name, data.value = target,
  data.method = kind, data.instrument = detail.

Run:  python3 tests/integration/test_actor_matrix.py
Env:  STAR_SERVER_URL (default http://127.0.0.1:15000)
"""
import json
import os
import time
import uuid
import unittest
import urllib.request
import urllib.error
import base64

BASE = os.environ.get("STAR_SERVER_URL", "http://127.0.0.1:15000")
COUCH = os.environ.get("COUCH_URL", "http://127.0.0.1:25984")
COUCH_DB = os.environ.get("COUCHDB_DATABASE", "starintel")
COUCH_USER = os.environ.get("COUCHDB_USER", "admin")
COUCH_PASS = os.environ.get("COUCHDB_PASSWORD", "starintel-test")

AUTH = base64.b64encode(f"{COUCH_USER}:{COUCH_PASS}".encode()).decode()


def http(method, url, body=None, headers=None, timeout=30):
    data = None
    hdrs = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode()
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw) if raw else None
        except json.JSONDecodeError:
            return e.code, raw.decode(errors="replace")


def couch(method, path, body=None):
    hdrs = {"Authorization": f"Basic {AUTH}"}
    return http(method, f"{COUCH}{path}", body, hdrs)


def submit_target(actor, target, options=None):
    body = {
        "target": target,
        "_id": f"target-{uuid.uuid4().hex}",
        "dtype": "target",
        "dataset": "starintel-universe-test",
        # The dispatch contract requires 1 <= delay <= 31536000.
        "delay": 1,
    }
    if options is not None:
        body["options"] = options
    return http("POST", f"{BASE}/new/target/{actor}", body)


def wait_for(predicate, timeout=60, interval=0.5, desc="condition"):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(interval)
    raise AssertionError(f"timeout waiting for {desc}: last={last!r}")


def couch_find(selector, limit=500):
    st, body = couch("POST", f"/{COUCH_DB}/_find",
                     {"selector": selector, "limit": limit})
    if st != 200:
        return []
    return body.get("docs", [])


def actor_docs(actor, target):
    return couch_find({"dtype": "observation",
                       "data.observer_id": actor,
                       "data.value": target})


def unique_prefix():
    return f"u{int(time.time() * 1000) % 100000000000}"


class ActorMatrix(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        st, body = http("GET", f"{BASE}/health")
        assert st == 200, f"stack not healthy: {st} {body}"
        cls.prefix = unique_prefix()

    # -- registry discovery + local routing ---------------------------
    def test_01_every_actor_routes(self):
        """All 11 deterministic actors are registered and routable."""
        expected = [
            "echo-actor", "transform-actor", "slow-actor",
            "streaming-actor", "crash-actor", "retry-actor",
            "invalid-result-actor", "producer-actor", "consumer-actor",
            "lease-race-actor", "config-reload-actor",
        ]
        for actor in expected:
            st, body = http("GET", f"{BASE}/targets/{actor}")
            self.assertEqual(st, 200, f"targets endpoint failed for {actor}")
        for actor in expected:
            st, _ = submit_target(actor, f"{self.prefix}-probe-{actor}")
            self.assertIn(st, (200, 201, 202),
                          f"routing failed for {actor} (not registered?)")
        # routing proof: probes for non-crashing actors produce results
        ok = wait_for(
            lambda: (ds if (ds := actor_docs("echo-actor",
                                             f"{self.prefix}-probe-echo-actor"))
                     else None),
            desc="probe echo result",
        )
        self.assertTrue(ok)

    # -- local routing + echo ----------------------------------------
    def test_10_echo_roundtrip(self):
        """Target -> local routing -> actor -> result enters StarIntel."""
        target = f"{self.prefix}-echo"
        st, _ = submit_target("echo-actor", target)
        self.assertIn(st, (200, 201, 202))
        docs = wait_for(lambda: actor_docs("echo-actor", target) or None,
                        desc="echo result document")
        self.assertEqual(docs[0]["data"]["method"], "echo")
        self.assertEqual(docs[0]["dataset"], "starintel-universe-test")

    # -- message serialization ----------------------------------------
    def test_11_serialization_preserves_payload(self):
        target = f"{self.prefix}-ser-ünïcode-✓"
        submit_target("echo-actor", target)
        docs = wait_for(lambda: actor_docs("echo-actor", target) or None,
                        desc="unicode echo result")
        self.assertEqual(docs[0]["data"]["value"], target)

    # -- options handling ----------------------------------------------
    def test_20_transform(self):
        target = f"{self.prefix}-xform"
        submit_target("transform-actor", target,
                      options=[{"op": "uppercase"}])
        docs = wait_for(
            lambda: [d for d in actor_docs("transform-actor", target)
                     if d["data"]["method"] == "transform-result"]
            or [d for d in couch_find(
                {"dtype": "observation", "data.observer_id": "transform-actor"})
                 if d["data"]["method"] == "transform-result"
                 and d["data"]["value"] == target.upper()] or None,
            desc="transform result",
        )
        self.assertEqual(docs[0]["data"]["value"], target.upper())
        self.assertEqual(docs[0]["data"]["instrument"], "uppercase")

    # -- actor-to-actor communication ----------------------------------
    def test_21_actor_to_actor_chain(self):
        ptarget = f"{self.prefix}-p2p"
        ctarget = f"{self.prefix}-p2p-consume"
        submit_target("producer-actor", ptarget, options=[{"count": 3}])
        submit_target("consumer-actor", ctarget)
        pdocs = wait_for(
            lambda: (ds if len(ds := actor_docs("producer-actor", ptarget)) >= 3
                     else None),
            desc="producer sequence",
        )
        self.assertEqual(sorted(d["data"]["instrument"] for d in pdocs),
                         ["1", "2", "3"])
        cdocs = wait_for(lambda: actor_docs("consumer-actor", ctarget) or None,
                         desc="consumer digest")
        self.assertGreaterEqual(int(cdocs[-1]["data"]["instrument"]), 1)

    # -- streaming ------------------------------------------------------
    def test_30_streaming(self):
        target = f"{self.prefix}-stream"
        submit_target("streaming-actor", target, options=[{"count": 4}])
        docs = wait_for(
            lambda: (ds if len(ds := actor_docs("streaming-actor", target)) >= 5
                     else None),
            desc="streaming parts + final",
        )
        progress = sorted(d["data"]["instrument"] for d in docs
                          if d["data"]["method"] == "progress")
        self.assertEqual(progress, ["1/4", "2/4", "3/4", "4/4"])
        finals = [d for d in docs if d["data"]["method"] == "final"]
        self.assertEqual(len(finals), 1)
        self.assertEqual(finals[0]["data"]["instrument"], "4")

    # -- slow actor -----------------------------------------------------
    def test_31_slow_actor(self):
        target = f"{self.prefix}-slow"
        submit_target("slow-actor", target, options=[{"seconds": 3}])
        docs = wait_for(lambda: actor_docs("slow-actor", target) or None,
                        timeout=90, desc="slow actor result")
        self.assertEqual(docs[0]["data"]["instrument"], "3")

    # -- crash: never a result, server healthy --------------------------
    def test_40_crash_never_yields_result(self):
        target = f"{self.prefix}-crash"
        submit_target("crash-actor", target)
        time.sleep(12)  # allow requeue/retry cycles
        self.assertEqual(actor_docs("crash-actor", target), [],
                         "crash-actor must never produce a result document")
        st, _ = http("GET", f"{BASE}/health")
        self.assertEqual(st, 200, "server must stay healthy after actor crash")

    # -- retry with eventual success -------------------------------------
    def test_41_retry_eventual_success(self):
        target = f"{self.prefix}-retry"
        submit_target("retry-actor", target, options=[{"attempts": 2}])
        docs = wait_for(
            lambda: [d for d in actor_docs("retry-actor", target)
                     if d["data"]["method"] == "retry-success"] or None,
            timeout=120, desc="retry actor eventual success")
        self.assertGreaterEqual(int(docs[0]["data"]["instrument"]), 2)

    # -- malformed output validation -------------------------------------
    def test_42_invalid_result_not_persisted(self):
        target = f"{self.prefix}-invalid"
        submit_target("invalid-result-actor", target)
        wait_for(lambda: actor_docs("invalid-result-actor", target) or None,
                 desc="invalid-result acknowledgement")
        time.sleep(5)
        bad = couch_find({"not": "a", "valid": "payload"})
        self.assertEqual(bad, [], "malformed payload must not persist")

    # -- stale registration ------------------------------------------------
    def test_43_stale_registration(self):
        st, _ = submit_target("no-such-actor-xyz", f"{self.prefix}-stale")
        self.assertIn(st, (200, 201, 202, 404, 409, 422))
        follow = f"{self.prefix}-after-stale"
        st2, _ = submit_target("echo-actor", follow)
        self.assertIn(st2, (200, 201, 202))
        docs = wait_for(lambda: actor_docs("echo-actor", follow) or None,
                        desc="echo after stale registration")
        self.assertTrue(docs)

    # -- concurrent identical targets --------------------------------------
    def test_50_concurrent_identical_targets(self):
        target = f"{self.prefix}-race"
        for _ in range(8):
            submit_target("lease-race-actor", target)
        docs = wait_for(
            lambda: (ds if (ds := actor_docs("lease-race-actor", target))
                     else None),
            timeout=90, desc="race actor report")
        deliveries = [d["data"]["instrument"] for d in docs]
        self.assertEqual(len(deliveries), len(set(deliveries)),
                         "delivery generations must be unique")

    # -- mailbox bounds / backpressure -------------------------------------
    def test_51_backpressure_flood(self):
        n = 25
        base = f"{self.prefix}-flood"
        for i in range(n):
            submit_target("echo-actor", f"{base}-{i}")

        def all_done():
            got = set()
            for d in couch_find({"dtype": "observation",
                                 "data.observer_id": "echo-actor"}):
                v = d["data"].get("value", "")
                if str(v).startswith(base):
                    got.add(v)
            return got if len(got) >= n else None

        got = wait_for(all_done, timeout=300, interval=2,
                       desc=f"{n} flood results")
        self.assertEqual(len(got), n)

    # -- config updates ------------------------------------------------------
    def test_60_config_reload(self):
        cfg = os.environ.get("STARINTEL_TEST_ACTOR_CONFIG")
        with open(cfg, "w") as f:
            f.write("mode=default\n")
        t1 = f"{self.prefix}-cfg1"
        submit_target("config-reload-actor", t1)
        d1 = wait_for(lambda: actor_docs("config-reload-actor", t1) or None,
                      desc="config result (default)")
        self.assertEqual(d1[0]["data"]["instrument"], "default")
        with open(cfg, "w") as f:
            f.write("mode=production\n")
        t2 = f"{self.prefix}-cfg2"
        submit_target("config-reload-actor", t2)
        d2 = wait_for(
            lambda: [d for d in actor_docs("config-reload-actor", t2)
                     if d["data"]["instrument"] == "production"] or None,
            desc="config result (production)")
        self.assertEqual(d2[0]["data"]["instrument"], "production")

    # -- HTTP boundary -------------------------------------------------------
    def test_70_http_rejects_garbage(self):
        st, _ = http("POST", f"{BASE}/new/target/echo-actor", None)
        self.assertIn(st, (400, 415, 422), "garbage body must 4xx")


if __name__ == "__main__":
    unittest.main(verbosity=2)
