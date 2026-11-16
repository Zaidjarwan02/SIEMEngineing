#!/usr/bin/env python3
"""Capture the post-enablement state as UTF-8 evidence.

Writes docs/evidence/12-rules-enabled-state.txt. Read-only against the cluster.
"""
import base64
import collections
import datetime
import json
import os
import urllib.error
import urllib.request

ES = "http://192.168.1.212:9200"
KB = "http://192.168.1.212:5601"
ADMIN = ("elastic", "<ADMIN_PASSWORD>")
TENANT1 = ("T1_user", "<TENANT1_PASSWORD>")
TKT = ("T2_user", "<TENANT2_PASSWORD>")
SPACES = ("default", "greencircle", "tkt")
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "evidence",
                   "12-rules-enabled-state.txt")

lines = []


def out(text=""):
    lines.append(str(text))


def call(base, path, auth=ADMIN, body=None, timeout=300):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data)
    token = base64.b64encode(f"{auth[0]}:{auth[1]}".encode()).decode()
    req.add_header("Authorization", "Basic " + token)
    req.add_header("kbn-xsrf", "true")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}


def status_only(base, path, auth=ADMIN, body=None, timeout=120):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data)
    token = base64.b64encode(f"{auth[0]}:{auth[1]}".encode()).decode()
    req.add_header("Authorization", "Basic " + token)
    req.add_header("kbn-xsrf", "true")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return "ERR"


out("POST-ENABLEMENT STATE EVIDENCE")
out("Captured: " + datetime.datetime.now().isoformat(timespec="seconds"))
out("Cluster: greencircle.SIEM / node-1 / Elasticsearch+Kibana 8.19.24 / Basic")
out("")

out("========== 1. CLUSTER HEALTH ==========")
_, h = call(ES, "/_cluster/health")
for k in ("cluster_name", "status", "number_of_nodes", "active_primary_shards",
          "active_shards", "unassigned_shards", "unassigned_primary_shards"):
    out(f"  {k}: {h.get(k)}")
out("")

out("========== 2. LICENSE + PACKAGE ==========")
_, lic = call(ES, "/_license")
out("  license: " + str((lic.get("license") or {}).get("type")) + " / " +
    str((lic.get("license") or {}).get("status")))
for sp in SPACES:
    _, pkg = call(KB, f"/s/{sp}/internal/detection_engine/prebuilt_rules/status")
    st = pkg.get("stats", {})
    out(f"  {sp}: installed={st.get('num_prebuilt_rules_installed')} "
        f"total_in_package={st.get('num_prebuilt_rules_total_in_package')}")
_, epm = call(KB, "/api/fleet/epm/packages/security_detection_engine")
item = epm.get("item", epm)
out(f"  security_detection_engine: {item.get('version')} / {item.get('status')}")
out("")

out("========== 3. RULE COUNTS / ENABLED / EXECUTION STATUS ==========")
all_rules = {}
for sp in SPACES:
    _, d = call(KB, f"/s/{sp}/api/detection_engine/rules/_find?per_page=10000&page=1")
    rules = d.get("data", [])
    all_rules[sp] = rules
    enabled = [r for r in rules if r.get("enabled")]
    statuses = collections.Counter(
        ((r.get("execution_summary") or {}).get("last_execution") or {}).get("status", "never")
        for r in enabled
    )
    out(f"  space {sp}: total={len(rules)} enabled={len(enabled)} "
        f"disabled={len(rules)-len(enabled)}")
    out(f"    execution status: {dict(statuses)}")
out("")

out("========== 4. FAILED / PARTIAL FAILURE REASONS (samples) ==========")
for sp in SPACES:
    reasons = collections.Counter()
    samples = {}
    for r in all_rules[sp]:
        if not r.get("enabled"):
            continue
        last = (r.get("execution_summary") or {}).get("last_execution") or {}
        if last.get("status") in ("failed", "partial failure"):
            msg = last.get("message") or last.get("error") or {}
            if isinstance(msg, dict):
                msg = msg.get("message") or json.dumps(msg)
            key = str(msg).split(". This warning")[0][:200]
            reasons[key] += 1
            samples.setdefault(key, r.get("name"))
    out(f"  --- {sp}: {sum(reasons.values())} failed/partial ---")
    for key, n in reasons.most_common(6):
        out(f"    [{n}] {key}")
        out(f"         e.g. {samples[key]}")
out("")

out("========== 5. API KEYS ==========")
_, keys = call(ES, "/_security/_query/api_key", body={"query": {"match_all": {}}, "size": 0})
out(f"  total api keys: {keys.get('total')}")
out("")

out("========== 6. ALERT INDICES ==========")
for pat in (".alerts-security.alerts-default*", ".internal.alerts-security.alerts-default*",
            ".alerts-security.alerts-greencircle*", ".internal.alerts-security.alerts-greencircle*",
            ".alerts-security.alerts-tkt*", ".internal.alerts-security.alerts-tkt*"):
    code, d = call(ES, f"/{pat}/_count")
    out(f"  {pat}: HTTP {code} count={d.get('count')}")
out("")

out("========== 7. DEFAULT ALERT DOCUMENTS ==========")
_, d = call(ES, "/.internal.alerts-security.alerts-default*/_search?size=10",
            body={"query": {"match_all": {}},
                  "_source": ["kibana.alert.rule.name", "kibana.alert.rule.rule_id",
                              "@timestamp", "kibana.alert.severity", "kibana.alert.risk_score",
                              "kibana.alert.workflow_status", "kibana.space_ids"]})
hits = d.get("hits", {})
out(f"  total: {hits.get('total', {}).get('value')}")
for hh in hits.get("hits", []):
    s = hh["_source"]
    out(f"  - {s.get('kibana.alert.rule.name')} | {s.get('kibana.alert.rule.rule_id')} | "
        f"{s.get('@timestamp')} | sev={s.get('kibana.alert.severity')} | "
        f"risk={s.get('kibana.alert.risk_score')} | status={s.get('kibana.alert.workflow_status')} | "
        f"spaces={s.get('kibana.space_ids')}")
out("")

out("========== 8. TENANT ACCESS MATRIX ==========")
matrix = [
    ("T1_user", TENANT1, "default alert index read", ES, "/.internal.alerts-security.alerts-default-000001/_search"),
    ("T1_user", TENANT1, "tkt alert index read (must be 403)", ES, "/.internal.alerts-security.alerts-tkt-000001/_search"),
    ("T1_user", TENANT1, "greencircle alert index read", ES, "/.internal.alerts-security.alerts-greencircle-000001/_search"),
    ("T2_user", TKT, "default alert index read", ES, "/.internal.alerts-security.alerts-default-000001/_search"),
    ("T2_user", TKT, "greencircle alert index read (must be 403)", ES, "/.internal.alerts-security.alerts-greencircle-000001/_search"),
    ("T2_user", TKT, "tkt alert index read", ES, "/.internal.alerts-security.alerts-tkt-000001/_search"),
]
for user, auth, label, base, path in matrix:
    out(f"  {user:9s} {label}: HTTP {status_only(base, path, auth)}")
for user, auth in (("T1_user", TENANT1), ("T2_user", TKT)):
    out(f"  {user:9s} default alert write (must be 403): HTTP "
        f"{status_only(ES, '/.alerts-security.alerts-default/_doc?refresh=true', auth, {'test': 'evidence'})}")
    out(f"  {user:9s} Kibana default alert search: HTTP "
        f"{status_only(KB, '/s/default/api/detection_engine/signals/search', auth, {'query': {'bool': {'must': []}}, 'size': 1})}")
    out(f"  {user:9s} Kibana default alerts page: HTTP "
        f"{status_only(KB, '/s/default/app/security/alerts', auth)}")
out("")

out("========== 9. TENANT ROLE DEFINITIONS ==========")
for role in ("greencircle", "tkt"):
    _, w = call(ES, f"/_security/role/{role}")
    d = w.get(role, {})
    out(f"  --- {role} ---")
    out(f"    cluster: {d.get('cluster')}")
    for i in d.get("indices", []):
        out(f"    index: {i.get('names')} -> {i.get('privileges')} "
            f"(restricted={i.get('allow_restricted_indices')})")
    for a in d.get("applications", []):
        out(f"    app: {a.get('application')} {a.get('privileges')} -> {a.get('resources')}")
out("")

out("========== 10. TENANT SPACE VISIBILITY ==========")
for user, auth in (("T1_user", TENANT1), ("T2_user", TKT)):
    _, d = call(KB, "/api/spaces/space", auth)
    out(f"  {user}: {sorted(s['id'] for s in d) if isinstance(d, list) else d}")
out("")

out("========== 11. RULE OWNERSHIP SAMPLE ==========")
for sp in ("greencircle", "tkt"):
    out(f"  --- {sp} ---")
    for r in all_rules[sp][:3]:
        out(f"    created_by={r.get('created_by')} updated_by={r.get('updated_by')} "
            f"enabled={r.get('enabled')} | {r.get('name')}")
out("")

out("========== END ==========")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print(f"wrote {os.path.abspath(OUT)} ({len(lines)} lines)")
