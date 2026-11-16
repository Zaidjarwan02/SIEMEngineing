#!/usr/bin/env python3
"""Enable every detection rule in one Kibana space, in batches.

Runs from the Windows workstation against the VM over HTTP, so long operations
are not constrained by the SSH command timeout.

Usage:
    python tools/enable_all_rules_http.py <space> [--dry-run]
    python tools/enable_all_rules_http.py <space> --user U --password P [--dry-run]

Known lab spaces use the built-in credentials below. For a new tenant, pass
--user/--password or set KB_USER/KB_PASSWORD. Bulk actions are capped by Kibana
at 100 rule ids per request.

Spaces/credentials are the lab accounts; rotate before non-lab use.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

KB = "http://192.168.1.212:5601"
CREDS = {
    "default": ("elastic", "<ADMIN_PASSWORD>"),
    "grcico-com": ("grc_user", "<TENANT1_PASSWORD>"),
    "tkt-org": ("tkt_user", "<TENANT2_PASSWORD>"),
}
BATCH = 100


def call(method, path, user, pwd, body=None, timeout=300):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(KB + path, data=data, method=method)
    token = base64.b64encode(f"{user}:{pwd}".encode("utf-8")).decode("ascii")
    req.add_header("Authorization", "Basic " + token)
    req.add_header("kbn-xsrf", "true")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def find_all(space, user, pwd):
    rules = []
    page = 1
    while True:
        path = (
            f"/s/{space}/api/detection_engine/rules/_find"
            f"?per_page=1000&page={page}&sort_field=created_at&sort_order=asc"
            f"&filter=alert.attributes.enabled:false"
        )
        code, raw = call("GET", path, user, pwd)
        if code != 200:
            raise SystemExit(f"find failed: HTTP {code}: {raw[:300]!r}")
        doc = json.loads(raw)
        rules.extend(doc.get("data", []))
        total = doc.get("total", len(rules))
        if len(rules) >= total or not doc.get("data"):
            break
        page += 1
    return rules, total


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: enable_all_rules_http.py <space> [--user U --password P] [--dry-run]")
        sys.exit(2)
    space = args[0]
    dry = "--dry-run" in args
    user = args[args.index("--user") + 1] if "--user" in args else os.environ.get("KB_USER")
    pwd = args[args.index("--password") + 1] if "--password" in args else os.environ.get("KB_PASSWORD")
    if (not user or not pwd) and space in CREDS:
        user, pwd = CREDS[space]
    if not user or not pwd:
        print("usage: enable_all_rules_http.py <space> --user U --password P [--dry-run]")
        print("       (or set KB_USER / KB_PASSWORD)")
        sys.exit(2)

    print(f"=== space {space} (as {user}) ===")
    t0 = time.time()
    rules, total = find_all(space, user, pwd)
    ids = [r["id"] for r in rules if r.get("id")]
    print(f"fetched {len(ids)} rules (API total {total}) in {time.time()-t0:.1f}s")
    if dry:
        print(f"dry-run: {len(ids)} disabled rules would be enabled")
        return

    enabled_now = 0
    failed_total = 0
    for start in range(0, len(ids), BATCH):
        chunk = ids[start:start + BATCH]
        t1 = time.time()
        code, raw = call(
            "POST",
            f"/s/{space}/api/detection_engine/rules/_bulk_action",
            user,
            pwd,
            {"action": "enable", "ids": chunk},
            timeout=500,
        )
        if code != 200:
            print(f"  batch {start//BATCH+1}: HTTP {code}: {raw[:300]!r}")
            failed_total += len(chunk)
            continue
        doc = json.loads(raw)
        summary = (doc.get("attributes") or {}).get("summary") or {}
        errors = doc.get("errors") or []
        failed_total += summary.get("failed", 0)
        enabled_now += summary.get("succeeded", 0)
        print(
            f"  batch {start//BATCH+1}: {len(chunk)} ids, "
            f"succeeded={summary.get('succeeded')} failed={summary.get('failed')} "
            f"skipped={summary.get('skipped')} errors={len(errors)} "
            f"[{time.time()-t1:.1f}s] progress={min(start+len(chunk), len(ids))}/{len(ids)}"
        )
        for err in errors[:3]:
            print(f"    error: {json.dumps(err)[:300]}")

    code, raw = call(
        "GET",
        f"/s/{space}/api/detection_engine/rules/_find"
        f"?per_page=1&filter=alert.attributes.enabled:true",
        user,
        pwd,
    )
    final = json.loads(raw).get("total") if code == 200 else "ERR"
    print(f"=== DONE {space}: enabled={final} batch_failed={failed_total} "
          f"elapsed={time.time()-t0:.1f}s ===")


if __name__ == "__main__":
    main()
