# 08 — Change Log

Chronological record of everything done to the test VM and the Elastic stack.
Phases 1–6 were performed on **2026-11-11**; phases 7–9 on **2026-11-12**.

> Nothing was deleted from the pre-existing tenants' data (there was none). The only
> deletions were test objects created by the verification scripts and one leftover test
> index.

## Phase 1 — Recover access to the VM

| # | Action | Detail |
|---|--------|--------|
| 1.1 | Powered on the VM | It was found powered off; IP `192.168.1.212` (MAC `08:00:27:17:56:d7`) |
| 1.2 | SSH login attempts failed | Guessed usernames were rejected and triggered temporary SSH throttling |
| 1.3 | Console recovery via GRUB | Booted with `init=/bin/bash`, mounted root read-write |
| 1.4 | Identified the human account | `user` (uid 1000, member of `sudo`) |
| 1.5 | Reset the account password | `echo 'user:<password>' \| chpasswd`; verified `passwd -S user` → `P` (password recorded in the test credentials file) |
| 1.6 | Rebooted normally | SSH confirmed working as `user` with sudo |

> This was a test VM; the password reset was the standard recovery path. Rotate this
> password before any non-lab use.

## Phase 2 — Audit and discovery (read-only)

| # | Action | Script | Output |
|---|--------|--------|--------|
| 2.1 | Full machine audit | `tools/audit.sh` | `docs/evidence/01-system-audit.txt` |
| 2.2 | Elasticsearch/Kibana discovery | `tools/es_discover.sh` | `docs/evidence/02-elastic-discovery.txt` |
| 2.3 | Roles, spaces, users baseline | `tools/es_roles.sh` | `docs/evidence/03-roles-spaces-baseline.txt` |
| 2.4 | Fleet, detection, heap baseline | `tools/es_fleet.sh` | `docs/evidence/04-fleet-detection-baseline.txt` |

Key findings: ES/Kibana 8.19.24, Basic license, cluster `grcico.SIEM`, spaces `default` /
`grcico-com` / `tkt-org`, roles `GreenCircle` / `tkt` with **overly broad `logs-*` /
`metrics-*` privileges**, no tenant users, Kibana encryption keys missing.

## Phase 3 — Fix Kibana encryption keys

| # | Action | Detail |
|---|--------|--------|
| 3.1 | Appended three keys to `/etc/kibana/kibana.yml` | `xpack.encryptedSavedObjects.encryptionKey`, `xpack.reporting.encryptionKey`, `xpack.security.encryptionKey` (random 32-byte hex each) |
| 3.2 | Restarted Kibana | `systemctl restart kibana`; available after ~21 s |
| 3.3 | Verified | `/api/status` → `available`; detection engine API returns `200` instead of `404` |

Script: `tools/fix_kibana_keys.sh`.

## Phase 4 — Provision tenant isolation

| # | Action | Detail |
|---|--------|--------|
| 4.1 | Rewrote role `GreenCircle` | `all` on `logs-*-greencircle*`, `metrics-*-greencircle*`, `traces-*-greencircle*`, `synthetics-*-greencircle*`, `profiling-*-greencircle*`, `grc-*`; `all` on its own alert indices; `space_all` on `space:grcico-com`; no cluster privileges |
| 4.2 | Rewrote role `tkt` | Same model with `tkt` namespace and `space:tkt-org` |
| 4.3 | Created user `grc_user` | Role `GreenCircle`; metadata `tenant=greencircle` |
| 4.4 | Created user `tkt_user` | Role `tkt`; metadata `tenant=tkt` |
| 4.5 | Created per-space data views | GreenCircle Logs/Metrics/Custom; TKT Logs/Metrics/Custom |

Script: `tools/provision_tenants.sh`.
Output: `docs/evidence/05-provisioning-output.txt`.

**Before → after for the roles:**

| | Before | After |
|---|--------|-------|
| GreenCircle indices | `logs-*`, `metrics-*` (all tenants) | `*-greencircle*`, `grc-*`, own alert indices only |
| tkt indices | `logs-*`, `metrics-*` (all tenants) | `*-tkt*`, `tkt-*`, own alert indices only |
| Users | none | `grc_user`, `tkt_user` |
| Data views | global `logs-*` / `metrics-*` | tenant-scoped per space |

Fleet policies and existing spaces were left unchanged.

## Phase 5 — Verification

| # | Action | Result |
|---|--------|--------|
| 5.1 | First isolation suite (`tools/verify_isolation.sh`) | 17 pass, 6 "fail" — all 6 were test-design artifacts (see below) |
| 5.2 | Cross-space diagnostic (`tools/diag_space.sh`) | Proved cross-space `_find` returns `total: 0`; direct GET/DELETE of foreign object → `403` |
| 5.3 | Data-stream diagnostic (`tools/diag_datastream.sh`) | Confirmed `logs-*`/`metrics-*` are data-stream-only templates |
| 5.4 | Stream write diagnostic (`tools/diag_stream_write.sh`) | Read own = 1, read other = 0, write own = 201, write other = 403 |
| 5.5 | Corrected suite (`tools/verify_isolation_final.sh`) | **PASS=40 FAIL=0** (suite later grew to 47 checks in phase 8) |
| 5.6 | Login-flow suite (`tools/verify_login.sh`) | Both users log in and land in their own space; default/foreign spaces → 403; bad creds → 401 (phase 8 later made Default read-only-shared) |

### The six initial "failures" and why they were not real

1–4. Elasticsearch wildcard searches over an unauthorized namespace return `200` with
`0` hits (unauthorized indices are dropped from the resolved set), not `403`. The corrected
test asserts `0` hits.
5–6. Kibana `/api/status` and saved-object `_find` are not denied with `403` for another
space; they return `200` with no data (`total: 0`). The corrected test asserts `total: 0`
and additionally checks that direct GET/DELETE of a known foreign object returns `403`.

## Phase 6 — Cleanup and final state

| # | Action | Detail |
|---|--------|--------|
| 6.1 | Deleted leftover test index | `grc-admin-test` (created during an early failed test) |
| 6.2 | Removed unnamed global data views | `logs-*` and `metrics-*` inside `grcico-com` and `tkt-org` |
| 6.3 | Removed all verification artifacts | Test data streams, test indices, test dashboards |
| 6.4 | Confirmed clean state | Cluster **green**, 48 shards, 0 unassigned; each tenant space has exactly 3 named data views; 0 tenant dashboards |

Final snapshot: `docs/evidence/08-final-state-snapshot.txt`.

## Phase 7 — Add `elastic/detection-rules` prebuilt rules (2026-11-12)

| # | Action | Detail |
|---|--------|--------|
| 7.1 | Verified registry connectivity | `epr.elastic.co` reachable; `security_detection_engine` 8.19.36 available, license `basic` |
| 7.2 | Cloned the source repo for reference | `github.com/elastic/detection-rules` → `%TEMP%\dr-repo` on Windows (2,348 TOML rules) |
| 7.3 | Installed the package | `POST /api/fleet/epm/packages/security_detection_engine {"force":true}` — 2,128 rules, 2,033 installable on Basic |
| 7.4 | Installed rules into Default | `POST /internal/detection_engine/prebuilt_rules/installation/_perform {"mode":"ALL_RULES"}` — 2,033/2,033 in 109 s |
| 7.5 | Installed rules into tenant spaces **as the tenant users** | `grc_user` → `grcico-com`, `tkt_user` → `tkt-org`; keeps rule API keys tenant-scoped |
| 7.6 | Removed duplicates | An interrupted first `grcico-com` install left 253 duplicate `rule_id`s; `tools/dr_dedup.sh` removed them → 2,033 unique |
| 7.7 | Set a uniform disabled baseline | Disabled the auto-enabled immutable `Endpoint Security (Elastic Defend)` rule in all three spaces → 0 enabled |
| 7.8 | Verified rule isolation | `tools/dr_verify_isolation.sh` — 9/9 at the time (own `200`, cross-space `403`) |

> Counts in phase 7 reflect package **8.19.36**. Phase 9 resynced everything to
> **8.19.37** (2,062 rules per space).

Details: [10-detection-rules.md](10-detection-rules.md).

## Phase 8 — Make Default a shared general space (2026-11-12)

Requirement: the Default space must be usable as a general shared area for all tenants,
while tenant data stays isolated.

| # | Action | Detail |
|---|--------|--------|
| 8.1 | Added `space_read` on `space:default` | To both `GreenCircle` and `tkt` roles; `space_all` on the own space unchanged |
| 8.2 | Verified read access | Both tenants see `default` + own space; can read Default dashboards and the 2,062 shared rules |
| 8.3 | Verified write denial | Creating/updating/deleting in Default → `403` for both tenants |
| 8.4 | Verified cross-tenant isolation unchanged | Other tenant's space still `403`; other tenant's data still `0` hits / `403` |

### Incident: role corruption and recovery (2026-11-12)

| # | Action | Detail |
|---|--------|--------|
| 8.5 | First role-update script corrupted both roles | `GET /_security/role/<name>` returns a wrapper `{"<name>": {...}}`; the parser read the wrapper and `PUT` an empty role. Both roles lost all `indices` and `cluster` entries and kept only `space_read` on `default` |
| 8.6 | Diagnosed from the API | Raw role JSON showed empty `indices`/`cluster`; tenant space lists showed only `default` |
| 8.7 | Restored canonical roles + shared Default | `tools/restore_roles_default_shared.sh` writes the full documented role JSON directly (no parsing) and adds `space_read` on `space:default` |
| 8.8 | Verified recovery | 2,062 rules and full read/write in own space restored; 47/47 isolation checks pass |

The buggy script `tools/add_default_space_access.sh` is retained for history but must not
be reused; `tools/restore_roles_default_shared.sh` is the supported path.

## Phase 9 — Package auto-upgrade and rule resync (2026-11-12)

| # | Action | Detail |
|---|--------|--------|
| 9.1 | Detected rule loss | Verification showed 0 rules in both tenant spaces and 1 enabled rule in Default |
| 9.2 | Root cause | Kibana auto-installed `security_detection_engine` **8.19.37** at 05:23 UTC (from 8.19.36). The upgrade removed tenant-space rule copies and re-enabled the immutable Endpoint rule |
| 9.3 | Resynced all spaces | `tools/dr_sync_space.sh` — install missing + upgrade outdated + disable all enabled. Result: **2,062 rules, 0 enabled** in `default`, `grcico-com`, `tkt-org` |
| 9.4 | Re-verified | `tools/dr_verify_isolation.sh` — **12/12**; `tools/verify_isolation_final.sh` — **47/47** |
| 9.5 | Captured post-change state | `docs/evidence/09-system-audit-after-rules.txt`, `docs/evidence/10-final-state-after-rules.txt`, `docs/evidence/11-detection-rules-verification.txt` |

## Phase 10 — Enable all detection rules and share Default alerts (2026-11-12)

Requirement: every `security_detection_engine` rule enabled for every tenant, the
Default space showing all tenants' alerts, and documented new-tenant steps.

| # | Action | Detail |
|---|--------|--------|
| 10.1 | Discovered the bulk-action API | `POST /s/<space>/api/detection_engine/rules/_bulk_action` supports `{"action":"enable","ids":[...]}`; max **100 ids** per request |
| 10.2 | Verified tenant enablement | A tenant user can enable a rule; Kibana creates the tenant-scoped API key automatically (API keys 51 → 52) |
| 10.3 | Enabled Default rules | 2,062/2,062 in `default` as `elastic`; 21 batches, zero failures, ~126 s |
| 10.4 | Enabled tenant rules | 2,062/2,062 in `grcico-com` as `grc_user` (~141 s) and `tkt-org` as `tkt_user` (~138 s); zero batch failures |
| 10.5 | Granted shared Default alert read | Added `read` + `view_index_metadata` on `.alerts-security.alerts-default*` and `.internal.alerts-security.alerts-default*` to both roles; tenants can view, not write |
| 10.6 | Verified alert visibility | Both tenants can search/read Default alerts (`200`), cannot write them (`403`); cross-tenant alert indices remain `403`; the attempted acknowledgement updated 0 docs and the alert stayed `open` |
| 10.7 | Captured state | 6,236 API keys; Default alert index 2 alerts; `tkt-org` 1 alert; execution status/failure reasons sampled |
| 10.8 | Extended verification | `tools/verify_isolation_final.sh` → **53/53**; `tools/dr_verify_isolation.sh` → **15/15**; login suite unchanged |
| 10.9 | Added new-tenant runbook | [11-add-new-tenant.md](11-add-new-tenant.md) with role JSON, space/user/data-view/rule/verify steps |

### Why many enabled rules report warnings/failures

- **Default space:** the global rule's expected integration/index is absent
  (e.g. `logs-aws.cloudtrail-*`, `logs-endpoint.events.process*`, `filebeat-*`).
- **Tenant spaces:** the rule API key is tenant-scoped, so it cannot read every
  index matched by a broad prebuilt pattern. The rule only sees the tenant's own
  data. This is the isolation model working as intended, not a leak.
- Enabling 6,186 rule instances (2,062 × 3) on one node also means rules are
  staggered; some show `never` until their first scheduled run.

## Files created

### Scripts (`D:\elasticMSSP\tools\`)

| Script | Purpose |
|--------|---------|
| `ssh_run.py` | Run a command over SSH |
| `remote_exec.py` | Upload a script and run it with sudo |
| `audit.sh` | Full read-only machine audit |
| `es_discover.sh` | Elasticsearch/Kibana discovery |
| `es_roles.sh` | Roles/spaces/users inspection |
| `es_fleet.sh` | Fleet/detection/heap inspection |
| `fix_kibana_keys.sh` | Add encryption keys and restart Kibana |
| `provision_tenants.sh` | Create roles, users, data views |
| `verify_isolation.sh` | First isolation suite (superseded) |
| `verify_isolation2.sh` | Diagnostic iteration (superseded) |
| `verify_isolation_final.sh` | **Authoritative** 47-check isolation suite |
| `verify_login.sh` | Kibana login/redirect/negative-auth suite |
| `dr_install_package.sh` | Install the `security_detection_engine` package |
| `dr_install_tenants.sh` | Install prebuilt rules in tenant spaces as tenant users |
| `dr_dedup.sh` | Remove duplicate prebuilt `rule_id`s in a space |
| `dr_disable_all.sh` | Disable every enabled rule in all spaces |
| `dr_sync_space.sh` | **Install + upgrade + disable** rules for one space (recovery) |
| `dr_verify_isolation.sh` | **Authoritative** 15-check detection-rule isolation + enablement suite |
| `enable_all_rules_http.py` | Enable all rules per space in batches of 100 over HTTP |
| `enable_verify_http.py` | Rule/enabled/execution-status/alert-count summary |
| `enable_verify_alerts.sh`, `enable_verify_alerts2.sh` | Tenant Default-alert access and write-denial probes |
| `state_after_enable.py` | Write the post-enablement evidence file (UTF-8) |
| `restore_roles_default_shared.sh` | **Canonical** role restore + shared Default read-only grant + Default alert read |
| `add_default_space_access.sh` | Superseded (wrapper-parsing bug); do not reuse |
| `diag_space.sh`, `diag_datastream.sh`, `diag_stream_write.sh` | Targeted diagnostics |
| `diag_pkg.sh`, `diag_rules_gone.sh`, `diag_rules2.sh`, `diag_rules3.sh` | Package / missing-rule / saved-object diagnostics |
| `find_leftovers.sh`, `quick_role_state.sh`, `step_probe.sh`, `step_probe2.sh`, `dr_probe_after_sync.sh` | Investigation helpers used during the shared-Default and rule-resync work |
| `cleanup_final.sh` | Remove leftover test objects |
| `snapshot_final.sh`, `snapshot_config.sh` | Final-state capture |
| `ocr_words.ps1`, `ocr.ps1`, `show_tls.py` | Console OCR / config display helpers |

### Documentation (`D:\elasticMSSP\docs\`)

This folder: README, 01–10, credentials file, and `evidence/`.

## Not changed

- Fleet agent policies (`grcico`, `tkt`, `Agent policy 1`) — left as-is.
- Existing spaces and their display names.
- Pre-existing `default` space content (40 dashboards) — now readable by tenants, still admin-writable only.
- Elasticsearch/Kibana versions.
- TLS, firewall, bind addresses, swap (documented in [hardening](07-hardening-checklist.md)).
