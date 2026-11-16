# 05 — Verification Evidence

**Result: `PASS=53 FAIL=0` — ALL ISOLATION TESTS PASSED**
Raw output: [`evidence/06-isolation-verification.txt`](evidence/06-isolation-verification.txt)
Login flow: [`evidence/07-login-flow-verification.txt`](evidence/07-login-flow-verification.txt)
Detection rules: [`evidence/11-detection-rules-verification.txt`](evidence/11-detection-rules-verification.txt)
Enabled-rule state: [`evidence/12-rules-enabled-state.txt`](evidence/12-rules-enabled-state.txt)

Executed 2026-11-12 against the live cluster. The suite creates real data streams and
saved objects, tests every boundary in both directions, then removes everything it created.
Counts are run-scoped (a unique `run_id` per execution) so pre-existing tenant data does
not affect the results. The suite was extended for the enabled-rule/Default-alert phase;
the current result is **53/53** isolation checks and **15/15** rule checks.

## How to reproduce

From `D:\elasticMSSP` on the Windows workstation:

```powershell
$env:PYTHONIOENCODING="utf-8"
python tools\remote_exec.py tools\verify_isolation_final.sh /tmp/verify_isolation_final.sh "bash /tmp/verify_isolation_final.sh"
python tools\remote_exec.py tools\dr_verify_isolation.sh /tmp/dr_verify_isolation.sh "bash /tmp/dr_verify_isolation.sh"
python tools\remote_exec.py tools\verify_login.sh /tmp/verify_login.sh "bash /tmp/verify_login.sh"
```

Scripts:

- `tools/verify_isolation_final.sh` — 53 data/space/alert isolation assertions
- `tools/dr_verify_isolation.sh` — 15 detection-rule isolation + enablement assertions
- `tools/verify_login.sh` — real Kibana login + redirect + negative auth tests

## Results by category

### 1. Elasticsearch data isolation (8 checks)

| Test | Expected | Got | Result |
|------|----------|-----|--------|
| greencircle_user reads own data stream | 200 | 200 | PASS |
| greencircle_user reads other data stream | 0 hits | 0 | PASS |
| greencircle_user writes own data stream | 201 | 201 | PASS |
| greencircle_user writes other data stream | 403 | 403 | PASS |
| tkt_user reads own data stream | 200 | 200 | PASS |
| tkt_user reads other data stream | 0 hits | 0 | PASS |
| tkt_user writes own data stream | 201 | 201 | PASS |
| tkt_user writes other data stream | 403 | 403 | PASS |

### 2. Wildcard namespace isolation (8 checks)

Counts are filtered by a per-run `run_id`, so they are exact regardless of existing data.

| Test | Expected | Got | Result |
|------|----------|-----|--------|
| greencircle_user sees own logs | 2 run docs | 2 | PASS |
| greencircle_user sees own metrics | 1 run doc | 1 | PASS |
| greencircle_user sees tkt logs | 0 | 0 | PASS |
| greencircle_user sees tkt metrics | 0 | 0 | PASS |
| tkt_user sees own logs | 2 run docs | 2 | PASS |
| tkt_user sees own metrics | 1 run doc | 1 | PASS |
| tkt_user sees greencircle logs | 0 | 0 | PASS |
| tkt_user sees greencircle metrics | 0 | 0 | PASS |

> **Why 0 hits instead of 403:** Elasticsearch resolves a wildcard to the concrete indices
> the user is allowed to see. Unauthorized indices are silently dropped from the resolved
> set, so a cross-tenant wildcard returns `200` with `0` hits. This is safe: no foreign
> document is ever returned. Direct access to a named foreign index returns `403`.

### 3. Alert-index isolation + shared Default alerts (8 checks)

| Test | Expected | Got | Result |
|------|----------|-----|--------|
| greencircle_user blocked from tkt alert index | 403 | 403 | PASS |
| tkt_user blocked from greencircle alert index | 403 | 403 | PASS |
| greencircle_user reads shared Default alerts | 200 | 200 | PASS |
| tkt_user reads shared Default alerts | 200 | 200 | PASS |
| greencircle_user writes shared Default alerts | 403 | 403 | PASS |
| tkt_user writes shared Default alerts | 403 | 403 | PASS |
| greencircle_user searches Default alerts in Kibana | 200 | 200 | PASS |
| tkt_user searches Default alerts in Kibana | 200 | 200 | PASS |

### 4. Kibana space-list visibility (4 checks)

Policy: each tenant sees the shared Default space plus its own space — never the other
tenant's space.

| Test | Result |
|------|--------|
| greencircle_user sees shared `default` | PASS |
| greencircle_user does not see `tkt` | PASS |
| tkt_user sees shared `default` | PASS |
| tkt_user does not see `greencircle` | PASS |

Actual responses:

```json
greencircle_user: [{"id":"default", ...}, {"id":"greencircle", "name":"greencircle", ...}]
tkt_user: [{"id":"default", ...}, {"id":"tkt",    "name":"tkt", ...}]
```

### 5. Kibana cross-space saved objects (8 checks)

| Test | Expected | Got | Result |
|------|----------|-----|--------|
| greencircle_user sees own dashboards | > 0 | yes | PASS |
| greencircle_user sees tkt dashboards | 0 | 0 | PASS |
| greencircle_user can read shared Default space | 200 | 200 | PASS |
| greencircle_user sees shared Default dashboards | > 0 | yes | PASS |
| tkt_user sees own dashboards | > 0 | yes | PASS |
| tkt_user sees greencircle dashboards | 0 | 0 | PASS |
| tkt_user can read shared Default space | 200 | 200 | PASS |
| tkt_user sees shared Default dashboards | > 0 | yes | PASS |

> Kibana's saved-object `_find` is space-filtered: querying the other tenant's space
> returns `200` with `total: 0`, not `403`. The data is not exposed. The Default space is
> intentionally readable.

### 6. Kibana cross-space write / direct access (11 checks)

| Test | Expected | Got | Result |
|------|----------|-----|--------|
| greencircle_user creates dashboard in own space | 200 | 200 | PASS |
| greencircle_user creates dashboard in tkt space | 403 | 403 | PASS |
| greencircle_user creates dashboard in default space | 403 | 403 | PASS |
| tkt_user creates dashboard in own space | 200 | 200 | PASS |
| tkt_user creates dashboard in greencircle space | 403 | 403 | PASS |
| tkt_user creates dashboard in default space | 403 | 403 | PASS |
| greencircle_user direct GET of a known tkt object | 403 | 403 | PASS |
| greencircle_user direct DELETE of a known tkt object | 403 | 403 | PASS |
| greencircle_user updates a shared Default object | 403 | 403 | PASS |
| greencircle_user deletes a shared Default object | 403 | 403 | PASS |
| tkt_user deletes a shared Default object | 403 | 403 | PASS |

The Default-space write checks use a disposable dashboard created by `elastic` and removed
by `elastic` after the assertions, so no shared content is touched.

### 7. Privilege-escalation checks (6 checks)

| Test | Expected | Got | Result |
|------|----------|-----|--------|
| greencircle_user reads security users | 403 | 403 | PASS |
| greencircle_user reads cluster health | 403 | 403 | PASS |
| greencircle_user creates an index outside its namespace | 403 | 403 | PASS |
| tkt_user reads security users | 403 | 403 | PASS |
| tkt_user reads cluster health | 403 | 403 | PASS |
| tkt_user creates an index outside its namespace | 403 | 403 | PASS |

## Detection-rule isolation and enablement (15 checks)

`tools/dr_verify_isolation.sh` — see [10-detection-rules.md](10-detection-rules.md).

| Test | Expected | Got | Result |
|------|----------|-----|--------|
| Default space has all 2,062 rules enabled | 2,062 | 2,062 | PASS |
| `greencircle` space has all 2,062 rules enabled | 2,062 | 2,062 | PASS |
| `tkt` space has all 2,062 rules enabled | 2,062 | 2,062 | PASS |
| greencircle_user can query own space rules | 200 | 200 | PASS |
| greencircle_user blocked from tkt rules | 403 | 403 | PASS |
| greencircle_user can read shared Default rules | 200 | 200 | PASS |
| greencircle_user sees shared Default rule set | 2,062 | 2,062 | PASS |
| tkt_user can query own space rules | 200 | 200 | PASS |
| tkt_user blocked from greencircle rules | 403 | 403 | PASS |
| tkt_user can read shared Default rules | 200 | 200 | PASS |
| tkt_user sees shared Default rule set | 2,062 | 2,062 | PASS |
| greencircle_user direct GET of a tkt rule | 403 | 403 | PASS |
| greencircle_user direct DELETE of a tkt rule | 403 | 403 | PASS |
| greencircle_user cannot fetch a tkt rule via Default | 404 | 404 | PASS |
| greencircle_user cannot create a rule in shared Default | 403 | 403 | PASS |

## Login-flow verification

The real Kibana login API was exercised with each user's credentials (not just Basic auth
on Elasticsearch):

| Check | greencircle_user | tkt_user |
|-------|----------|----------|
| `POST /internal/security/login` | `200 {"location":"/"}` | `200 {"location":"/"}` |
| `GET /` redirect | `/spaces/space_selector` | `/spaces/space_selector` |
| `GET /api/spaces/space` | `default` + `greencircle` | `default` + `tkt` |
| `GET /app/home` (Default) | 200 | 200 |
| `GET /app/dashboards` (Default) | 200 | 200 |
| `GET /s/greencircle/app/dashboards` | 200 | 403 |
| `GET /s/tkt/app/dashboards` | 403 | 200 |

Because each user can now access **two** spaces, Kibana redirects `/` to the **space
selector** instead of auto-entering a single space. Each user picks Default (shared) or
their own space. Access to the other tenant's space remains `403`.

## Negative auth checks

| Test | Result |
|------|--------|
| `greencircle_user` with wrong password | `401` |
| unknown user | `401` |

## Final state after verification

- Cluster health: **yellow** (single node, unassigned replicas — expected).
- All test data streams, indices, and dashboards removed.
- Tenant spaces contain only their three named data views (plus Kibana-managed objects).
- Default space: 2,062 shared detection rules, **all enabled**.
- Each tenant space: 2,062 detection rules, **all enabled**, created by the tenant user.
- Detection-engine API keys: **6,236**.
- Default alert index: **2 alerts** at capture; tenant alert indices contain their own alerts.
- Default alerts: readable by both tenants, not writable (`403`).
