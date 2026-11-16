# 09 — Raw Evidence Index

All raw command output is stored in [`docs/evidence/`](evidence/) as UTF-8 text, captured
directly from the VM. These files are the primary source for the summaries in this
documentation set.

| File | Source script | Captured | Contents |
|------|---------------|----------|----------|
| `evidence/01-system-audit.txt` | `tools/audit.sh` | 2026-11-11 | Host identity, CPU/RAM/disk, network, users, packages, services, ports, ES/Kibana API, security posture, logs, cron |
| `evidence/02-elastic-discovery.txt` | `tools/es_discover.sh` | 2026-11-11 | ES root, cluster health, nodes, license, indices, data streams, templates, users, roles, role mappings, API keys, snapshots, spaces, config, JVM heap, certs |
| `evidence/03-roles-spaces-baseline.txt` | `tools/es_roles.sh` | 2026-11-11 | Baseline `GreenCircle`/`tkt` role definitions, users (none), spaces, features, saved objects, ES/Kibana logs |
| `evidence/04-fleet-detection-baseline.txt` | `tools/es_fleet.sh` | 2026-11-11 | Fleet policies/enrollment/outputs/settings, detection rules/status, alert indices, heap, Kibana keystore, encryption-key presence, per-space index patterns |
| `evidence/05-provisioning-output.txt` | `tools/provision_tenants.sh` | 2026-11-11 | Role/user/data-view creation responses, final role/user definitions, per-user space visibility |
| `evidence/06-isolation-verification.txt` | `tools/verify_isolation_final.sh` | 2026-11-12 | **53/53** isolation assertions with expected vs actual values |
| `evidence/07-login-flow-verification.txt` | `tools/verify_login.sh` | 2026-11-12 | Real Kibana login, redirect target (space selector), space visibility, per-space app access, negative auth |
| `evidence/08-final-state-snapshot.txt` | `tools/snapshot_final.sh` | 2026-11-12 | Full final state: cluster, users, roles (incl. shared Default), spaces, data views, dashboards, **detection-rule counts**, Fleet, masked keys, security posture |
| `evidence/09-system-audit-after-rules.txt` | `tools/audit.sh` | 2026-11-12 | Full host/stack audit after the detection-rules and shared-Default changes |
| `evidence/10-final-state-after-rules.txt` | `tools/snapshot_final.sh` (extract) | 2026-11-12 | Focused post-rules state: cluster, roles, spaces, rule counts, dashboards |
| `evidence/11-detection-rules-verification.txt` | `tools/dr_verify_isolation.sh` | 2026-11-12 | **15/15** detection-rule isolation + enablement assertions, ownership and counts |
| `evidence/12-rules-enabled-state.txt` | `tools/state_after_enable.py` | 2026-11-12 | Post-enablement state: 2,062 enabled per space, 6,236 API keys, execution status, failure reasons, alert counts, tenant access matrix, role JSON |

## Notes on capture

- Commands were run through `tools/remote_exec.py`, which uploads a local script to
  `/tmp`, runs it with `sudo`, and streams UTF-8 output back.
- Windows PowerShell sometimes writes redirected output as UTF-16. Raw captures were
  decoded to UTF-8 before being saved into `docs/evidence/`.
- Kibana encryption key values are **masked** in the snapshot and never appear in this
  documentation.
- The `kibana_system` password is redacted wherever it would otherwise be shown.

## Sensitive data handling

The evidence files contain internal hostnames, IP addresses, index names, and role
definitions. They do **not** contain the Kibana encryption key values or the
`kibana_system` password. Test account passwords are kept separately in
[`credentials-test-only.md`](credentials-test-only.md).

Before sharing this folder outside the lab:

1. Remove or redact `credentials-test-only.md`.
2. Review the audit log excerpts for any secrets.
3. Treat the folder as internal.
