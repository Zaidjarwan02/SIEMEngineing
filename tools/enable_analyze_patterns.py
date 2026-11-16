#!/usr/bin/env python3
"""Analyse index patterns of enabled Default rules vs tenant namespaces."""
import base64
import collections
import json
import urllib.request

KB = "http://192.168.1.212:5601"
ADMIN = ("elastic", "<ADMIN_PASSWORD>")


def call(path, timeout=180):
    req = urllib.request.Request(KB + path)
    token = base64.b64encode(f"{ADMIN[0]}:{ADMIN[1]}".encode()).decode()
    req.add_header("Authorization", "Basic " + token)
    req.add_header("kbn-xsrf", "true")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


d = call("/s/default/api/detection_engine/rules/_find?per_page=10000&page=1")
rules = [r for r in d.get("data", []) if r.get("enabled")]
patterns = collections.Counter()
broad = []
for r in rules:
    idx = r.get("index") or []
    for p in idx:
        patterns[p] += 1
    # Does any pattern match logs-test-greencircle / logs-test-tkt?
    for p in idx:
        if p in ("logs-*", "*", "logs-*-*", "logs-*-greencircle*", "logs-*-tkt*"):
            broad.append((r.get("name"), idx))
            break

print("enabled default rules:", len(rules))
print("distinct index patterns:", len(patterns))
print("\ntop 25 patterns:")
for p, n in patterns.most_common(25):
    print(f"  {n:5d}  {p}")

print("\nrules whose patterns include a broad/tenant match:", len(broad))
for name, idx in broad[:20]:
    print("  ", name, "->", idx)

# How many rules use logs-* exactly
print("\nrules with exact logs-*:", sum(1 for r in rules if "logs-*" in (r.get("index") or [])))
print("rules with exact *:", sum(1 for r in rules if "*" in (r.get("index") or [])))
