#!/usr/bin/env python3
"""Summarise enabled detection rules and alert indices after enablement."""
import base64
import collections
import json
import urllib.request

ES = "http://192.168.1.212:9200"
KB = "http://192.168.1.212:5601"
ADMIN = ("elastic", "<ADMIN_PASSWORD>")
SPACES = ["default", "grcico-com", "tkt-org"]


def call(base, path, auth=ADMIN, body=None, timeout=300):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data)
    token = base64.b64encode(f"{auth[0]}:{auth[1]}".encode()).decode()
    req.add_header("Authorization", "Basic " + token)
    req.add_header("kbn-xsrf", "true")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


for sp in SPACES:
    d = call(KB, f"/s/{sp}/api/detection_engine/rules/_find?per_page=10000&page=1")
    rules = d.get("data", [])
    enabled = [r for r in rules if r.get("enabled")]
    statuses = collections.Counter(
        ((r.get("execution_summary") or {}).get("last_execution") or {}).get("status", "never")
        for r in enabled
    )
    types = collections.Counter(r.get("type") for r in enabled)
    print(f"space {sp}: total={len(rules)} enabled={len(enabled)}")
    print(f"  execution status: {dict(statuses)}")
    print(f"  rule types: {dict(types)}")

print("\n=== ALERT INDEX COUNTS (admin) ===")
for pat in [
    ".alerts-security.alerts-default*",
    ".internal.alerts-security.alerts-default*",
    ".alerts-security.alerts-grcico-com*",
    ".internal.alerts-security.alerts-grcico-com*",
    ".alerts-security.alerts-tkt-org*",
    ".internal.alerts-security.alerts-tkt-org*",
]:
    try:
        d = call(ES, f"/{pat}/_count")
        print(f"  {pat}: {d.get('count')}")
    except Exception as e:
        print(f"  {pat}: ERROR {e}")

print("\n=== API KEYS ===")
d = call(ES, "/_security/_query/api_key", body={"query": {"match_all": {}}, "size": 0})
print("  total:", d.get("total"))
