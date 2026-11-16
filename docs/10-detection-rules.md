# 10 — Detection Rules (elastic/detection-rules)

## What was added

The Elastic prebuilt detection-rule set — the packaged, license-aware form of
[`github.com/elastic/detection-rules`](https://github.com/elastic/detection-rules) — is
installed in **all three Kibana spaces**:

| Space | Rules installed | Created by | Enabled |
|-------|-----------------|------------|---------|
| `default` (shared general) | 2,062 | `elastic` | **2,062** |
| `greencircle` (Tenant 1) | 2,062 | `T1_user` | **2,062** |
| `tkt` (TKT) | 2,062 | `T2_user` | **2,062** |

Package: `security_detection_engine` **v8.19.37** (license `basic`).
Package total: 2,157 rules; **2,062 installable on the Basic license** (95 require a
higher license and are skipped by Kibana).

## Why the packaged form instead of importing the repo's TOML files

- The repo contains ~2,348 TOML rule sources, but the supported install path is the
  signed `security_detection_engine` package served by the Elastic Package Registry
  (`epr.elastic.co`), which Kibana already trusts.
- The package is version-matched to Kibana 8.19.x, applies license filtering, and
  supports install/upgrade through Kibana's prebuilt-rules API.
- Importing raw TOML would require the repo's Python tooling, which the VM does not
  have (no `pip`, no `git`), and would bypass license/version checks.

The repo was still cloned on the Windows workstation (`%TEMP%\dr-repo`, 2,348 TOML files)
to confirm it is the same rule corpus.

## Where the rules live and why

The user requirement was **Default space as the shared general area for all tenants**,
and rules in **Default + tenant spaces**:

- **Default** — one shared rule set, readable by both tenants via `space_read`. Tenants
  cannot create, edit, disable or delete these rules (`403` verified).
- **`greencircle` / `tkt`** — a tenant-scoped copy in each space so a tenant can
  manage its own detections without touching shared content. Each copy was installed
  **as the tenant user**, so every rule's API key is scoped to that tenant's role and
  namespace. A tenant editing its own rule cannot make it query another tenant's data.

Installing the tenant copies as `elastic` would have produced rules whose API keys can
read every index; that is why the install was done as `T1_user` / `T2_user`.

## Enabled state: all 2,062 rules in every space

All 2,062 rules in all three spaces are **enabled**:

| Space | Enabled | API key owner | Alert index |
|-------|---------|---------------|-------------|
| `default` | 2,062 / 2,062 | `elastic` (global) | `.alerts-security.alerts-default*` |
| `greencircle` | 2,062 / 2,062 | `T1_user` (tenant-scoped) | `.alerts-security.alerts-greencircle*` |
| `tkt` | 2,062 / 2,062 | `T2_user` (tenant-scoped) | `.alerts-security.alerts-tkt*` |

Total detection-engine API keys after enablement: **6,236**.

### How the rules were enabled

Kibana's bulk-action API accepts at most **100 rule ids per request**. Enabling
2,062 rules therefore takes 21 batches. The helper script does this
automatically:

```bash
python tools/enable_all_rules_http.py default
python tools/enable_all_rules_http.py greencircle
python tools/enable_all_rules_http.py tkt
```

It fetches only the disabled rules (`filter=alert.attributes.enabled:false`),
sends `{"action":"enable","ids":[...]}` in chunks of 100, and reports the final
enabled count. The API also accepts a query form:

```json
{"action":"enable","query":"alert.attributes.name:\"...\""}
```

Individual rules can still be toggled in the UI or with:

```bash
curl -u "T1_user:<password>" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X PATCH "http://192.168.1.212:5601/s/greencircle/api/detection_engine/rules" \
  -d '{"rule_id":"<rule_id>","enabled":true}'
```

> Tenant users can enable rules without `manage_own_api_key`; Kibana creates the
> rule API key automatically and scopes it to the tenant role.

### Execution status is not the same as "enabled"

Enabling a rule only schedules it. Many prebuilt rules report **partial failure**
or **failed** because the integrations/indices they expect do not exist on this
lab, and the tenant-space copies are deliberately limited to tenant data:

- **Default space (global API keys):** failures are mostly
  "no index matching `logs-aws.cloudtrail-*`, `logs-endpoint.events.process*`,
  `filebeat-*`, ..." — the integration is not installed.
- **Tenant spaces (tenant-scoped API keys):** failures are mostly
  "This rule's API key is unable to access all indices that match ..." — the
  tenant role only grants its own namespace. This is **isolation working as
  designed**, not a leak. The rule still only sees the tenant's data.
- A snapshot after enablement showed Default
  `{partial failure: 1772, succeeded: 148, failed: 142}`; tenant spaces varied as
  their schedules ran. These numbers change every interval and are not a health
  score.

The immutable `Endpoint Security (Elastic Defend)` rule is enabled along with
the rest; it reports failures when no Elastic Defend integration is present.

## Install / upgrade procedure

Kibana's prebuilt-rules API is internal and uses `mode: "ALL_RULES"` (not `"ALL"`).

```bash
# 1. Ensure the package is installed (Kibana may also auto-install it)
curl -u "elastic:<pw>" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "http://127.0.0.1:5601/api/fleet/epm/packages/security_detection_engine" \
  -d '{"force":true}'

# 2. Install missing rules and upgrade outdated ones, per space, as that space's user
#    (use tools/dr_sync_space.sh <space> <user:pass> which does both)
# 3. Enable all rules (use tools/enable_all_rules_http.py <space>)
```

`tools/dr_sync_space.sh` performs, for one space:

1. `GET  /s/<space>/internal/detection_engine/prebuilt_rules/status`
2. `POST /s/<space>/internal/detection_engine/prebuilt_rules/installation/_perform` `{"mode":"ALL_RULES"}`
3. `POST /s/<space>/internal/detection_engine/prebuilt_rules/upgrade/_perform` `{"mode":"ALL_RULES"}`
4. Reports final count and enabled count

> Older versions of this script disabled every enabled rule to restore a quiet
> baseline. For the current enabled deployment, do **not** run the disable step;
> run the install/upgrade and then `enable_all_rules_http.py`.

Typical timings: 5–10 s for an upgrade, ~120 s for a fresh 2,062-rule install per space,
and ~130–140 s to enable 2,062 rules in one space.

## Package auto-upgrade incident (important)

During this work Kibana **auto-installed `security_detection_engine` 8.19.37** (from
8.19.36) at 2026-11-12 05:23 UTC. That package upgrade:

- removed the prebuilt rule copies from `greencircle` and `tkt` (they dropped to 0), and
- re-enabled the immutable Endpoint Security rule in `default`.

All three spaces were resynced to 2,062 rules and then re-enabled. Because Kibana can
auto-upgrade this package again, treat rule counts as something to re-check after any
package or Kibana version change:

```bash
python tools/remote_exec.py tools/dr_verify_isolation.sh /tmp/dr_verify_isolation.sh \
  "bash /tmp/dr_verify_isolation.sh"
```

If a tenant space shows 0 rules, re-run:

```bash
python tools/remote_exec.py tools/dr_sync_space.sh /tmp/dr_sync_space.sh \
  "bash /tmp/dr_sync_space.sh greencircle T1_user:<password>"
python tools/remote_exec.py tools/dr_sync_space.sh /tmp/dr_sync_space.sh \
  "bash /tmp/dr_sync_space.sh tkt T2_user:<password>"
```

## Verification

`tools/dr_verify_isolation.sh` — **PASS=15 FAIL=0**:

- 2,062 rules in each space; **2,062 enabled in each space**.
- Tenant-space rules show `created_by` = the tenant user.
- `T1_user` / `T2_user` can query their own space rules (`200`).
- Cross-tenant rule queries are `403`.
- Tenants can read the shared Default rule set (`200`, 2,062 rules).
- A tenant cannot fetch a foreign rule through the Default space (`404`) and cannot
  create a rule in Default (`403`).
- Direct GET/DELETE of a foreign rule in the foreign space is `403`.

Full raw output: [evidence/11-detection-rules-verification.txt](evidence/11-detection-rules-verification.txt)
and [evidence/12-rules-enabled-state.txt](evidence/12-rules-enabled-state.txt).

## Default-space alert visibility

The Default space is the shared, read-only alert view for every tenant:

- Default has its own **global** rule set (2,062 enabled rules) whose API keys can
  query all tenant data. Those rules write to
  `.alerts-security.alerts-default*`.
- Both tenant roles have `read` + `view_index_metadata` on
  `.alerts-security.alerts-default*` and `.internal.alerts-security.alerts-default*`.
- Tenants can open **Security → Alerts** in Default and search the Default alert
  index (`200`), but cannot acknowledge, close, or write alerts (`403`).
- Tenant-space alerts stay in the tenant's own alert index. Direct reads of
  another tenant's alert index return `403`; wildcard reads return `0` hits.

At the time of capture the Default alert index held **2 alerts** and the
`tkt` alert index held **1 alert** generated by the tenant-scoped rule set.

## Limitations and risks

| Item | Note |
|------|------|
| Basic license | 95 of 2,157 packaged rules are not installable; they are skipped, not failed. |
| Rule churn | Package auto-upgrades can reset counts/enabled state — re-run the sync, enablement and verification after upgrades. |
| Enabled ≠ healthy | Many rules report `partial failure`/`failed` because the matching integration or index is absent, or because a tenant-scoped API key cannot read another tenant's index. This is expected on the lab. |
| Scheduler load | 6,186 enabled rule instances (2,062 × 3 spaces) on one node. Rules are staggered; some show `never` until their first run. This is not an isolation failure. |
| Alert indices | Alerts are space-scoped: `.alerts-security.alerts-greencircle*`, `.alerts-security.alerts-tkt*`, and the Default alert index. Tenants cannot read each other's alert indices. |
| Default alert volume | The Default global rule set duplicates detection work already done by tenant-space copies. Duplicate computation is accepted in this lab for the shared view. |
| Rule actions | Advanced actions (e.g., some third-party connectors) may require a higher license or additional Fleet setup. |
