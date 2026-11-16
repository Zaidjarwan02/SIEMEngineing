#!/usr/bin/env python3
"""Sample execution failures / partial failures from enabled detection rules."""
import base64
import collections
import json
import urllib.request

KB = "http://192.168.1.212:5601"
ADMIN = ("elastic", "<ADMIN_PASSWORD>")


def call(path, body=None, timeout=180):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(KB + path, data=data)
    token = base64.b64encode(f"{ADMIN[0]}:{ADMIN[1]}".encode()).decode()
    req.add_header("Authorization", "Basic " + token)
    req.add_header("kbn-xsrf", "true")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


for space in ("default", "greencircle", "tkt"):
    d = call(f"/s/{space}/api/detection_engine/rules/_find?per_page=10000&page=1")
    rules = d.get("data", [])
    reasons = collections.Counter()
    samples = {}
    for r in rules:
        if not r.get("enabled"):
            continue
        last = (r.get("execution_summary") or {}).get("last_execution") or {}
        status = last.get("status", "never")
        if status in ("failed", "partial failure"):
            msg = last.get("message") or last.get("error") or {}
            if isinstance(msg, dict):
                msg = msg.get("message") or json.dumps(msg)
            key = str(msg)[:220]
            reasons[key] += 1
            samples.setdefault(key, r.get("name"))
    print(f"\n===== {space}: {sum(reasons.values())} failed/partial =====")
    for key, n in reasons.most_common(8):
        print(f"  [{n}] {key}")
        print(f"       e.g. {samples[key]}")
