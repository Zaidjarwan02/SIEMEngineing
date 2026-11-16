# 03 — Tenant Design

## Goal

One account per tenant user that has **full read/write inside its own tenant** and
**zero visibility of any other tenant**, at both the Elasticsearch data layer and the
Kibana UI layer.

## Isolation model: space + namespace + role

```
                        ┌─────────────────────────────────────────────┐
                        │              Elasticsearch                   │
                        │              cluster grcico.SIEM             │
                        │                                             │
  grc_user ──role──►    │  logs-*-greencircle*   metrics-*-greencircle*│
  (GreenCircle)         │  traces-*-greencircle* synthetics-*-...      │
                        │  grc-*                                       │
                        │  .alerts-security.alerts-grcico-com*         │
                        │                                             │
  tkt_user ──role──►    │  logs-*-tkt*   metrics-*-tkt*                │
  (tkt)                 │  traces-*-tkt* synthetics-*-tkt*             │
                        │  tkt-*                                       │
                        │  .alerts-security.alerts-tkt-org*            │
                        └─────────────────────────────────────────────┘

                        ┌─────────────────────────────────────────────┐
                        │                 Kibana                       │
                        │  Space grcico-com  ◄── grc_user (space_all)  │
                        │  Space tkt-org     ◄── tkt_user  (space_all) │
                        │  Space default     ◄── both users (space_read)│
                        │      shared "general" space, read-only       │
                        └─────────────────────────────────────────────┘
```

Isolation is enforced in **three independent layers**:

1. **Elasticsearch index privileges** — the role only names that tenant's index/data-stream
   patterns. Elasticsearch refuses reads/writes outside them.
2. **Kibana space privileges** — the role grants `space_all` on exactly one space resource
   (`space:grcico-com` or `space:tkt-org`) and `space_read` on `space:default`. Kibana hides
   the other tenant's space entirely; the Default space is visible but read-only.
3. **Per-space data views** — each tenant space only contains data views whose titles match
   that tenant's namespace, so the UI cannot even offer another tenant's data.

## Tenant mapping

| Tenant | Space ID | Space name | ES role | User | Index / data-stream patterns |
|--------|----------|------------|---------|------|------------------------------|
| GreenCircle | `grcico-com` | greencircle | `GreenCircle` | `grc_user` | `logs-*-greencircle*`, `metrics-*-greencircle*`, `traces-*-greencircle*`, `synthetics-*-greencircle*`, `profiling-*-greencircle*`, `grc-*` |
| TKT | `tkt-org` | tkt | `tkt` | `tkt_user` | `logs-*-tkt*`, `metrics-*-tkt*`, `traces-*-tkt*`, `synthetics-*-tkt*`, `profiling-*-tkt*`, `tkt-*` |

## Role definitions (effective)

### `GreenCircle`

```json
{
  "cluster": [],
  "indices": [
    {
      "names": ["logs-*-greencircle*", "metrics-*-greencircle*", "traces-*-greencircle*",
                "synthetics-*-greencircle*", "profiling-*-greencircle*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": ["grc-*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": [".alerts-security.alerts-grcico-com*", ".internal.alerts-security.alerts-grcico-com*"],
      "privileges": ["all"],
      "allow_restricted_indices": true
    },
    {
      "names": [".alerts-security.alerts-default*", ".internal.alerts-security.alerts-default*"],
      "privileges": ["read", "view_index_metadata"],
      "allow_restricted_indices": true
    }
  ],
  "applications": [
    { "application": "kibana-.kibana", "privileges": ["space_all"],  "resources": ["space:grcico-com"] },
    { "application": "kibana-.kibana", "privileges": ["space_read"], "resources": ["space:default"] }
  ],
  "description": "GreenCircle tenant: full read/write on greencircle data and grc-* only; full UI in space grcico-com; read-only in shared Default space and its alerts."
}
```

### `tkt`

```json
{
  "cluster": [],
  "indices": [
    {
      "names": ["logs-*-tkt*", "metrics-*-tkt*", "traces-*-tkt*",
                "synthetics-*-tkt*", "profiling-*-tkt*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": ["tkt-*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": [".alerts-security.alerts-tkt-org*", ".internal.alerts-security.alerts-tkt-org*"],
      "privileges": ["all"],
      "allow_restricted_indices": true
    },
    {
      "names": [".alerts-security.alerts-default*", ".internal.alerts-security.alerts-default*"],
      "privileges": ["read", "view_index_metadata"],
      "allow_restricted_indices": true
    }
  ],
  "applications": [
    { "application": "kibana-.kibana", "privileges": ["space_all"],  "resources": ["space:tkt-org"] },
    { "application": "kibana-.kibana", "privileges": ["space_read"], "resources": ["space:default"] }
  ],
  "description": "TKT tenant: full read/write on tkt data and tkt-* only; full UI in space tkt-org; read-only in shared Default space and its alerts."
}
```

### Why no `cluster` privileges

Tenants deliberately have **no cluster-level privileges**. They cannot read cluster health,
manage indices, read the security API, create indices outside their namespace, or see
other users. This was verified.

## Data views per space

| Space | Data view name | Pattern |
|-------|----------------|---------|
| `grcico-com` | GreenCircle Logs | `logs-*-greencircle*` |
| `grcico-com` | GreenCircle Metrics | `metrics-*-greencircle*` |
| `grcico-com` | GreenCircle Custom (grc-*) | `grc-*` |
| `tkt-org` | TKT Logs | `logs-*-tkt*` |
| `tkt-org` | TKT Metrics | `metrics-*-tkt*` |
| `tkt-org` | TKT Custom (tkt-*) | `tkt-*` |

Legacy unnamed global `logs-*` / `metrics-*` data views were removed from the tenant
spaces so the UI only offers tenant-scoped patterns.

## Alert index scoping

Security detection alerts are stored in space-specific hidden indices:

- GreenCircle: `.alerts-security.alerts-grcico-com*` and `.internal.alerts-security.alerts-grcico-com*`
- TKT: `.alerts-security.alerts-tkt-org*` and `.internal.alerts-security.alerts-tkt-org*`
- Default (shared): `.alerts-security.alerts-default*` and `.internal.alerts-security.alerts-default*`

The tenant role can read/write only its own alert indices. Cross-tenant alert access
returns `403` (verified). Both tenant roles also have **read-only** access to the
Default alert indices, so each tenant can see the shared cross-tenant alert view in
the Default space. They cannot acknowledge, close, or write those alerts (`403`
verified; the alert workflow status remains `open` after an attempted update).

The Default space's own global rule set (2,062 rules, enabled by `elastic`) uses
global API keys, so it can query every tenant's data and write the resulting alerts
into the Default alert index. That is how the Default space shows all tenants'
alerts without exposing any tenant's raw indices.

## Why namespace isolation instead of document-level security (DLS)

Document-level security would require a reliable tenant field on every document. The
current ingest pipeline does **not** add one, so DLS would either be unenforceable or
require a risky reindex/transform. Namespace isolation is deterministic, works with
Fleet data streams out of the box, and is easy to audit.

If tenant data must later share a single index, add a mandatory `tenant` field at ingest
and revisit DLS or field-level security.

## What a tenant can do

- Log in to Kibana and choose between the shared Default space and its own space.
- Use Discover, Dashboards, Visualize, Alerting, and detection rules **inside its space**.
- Read and write documents in its own log/metric/custom namespaces.
- Create new data streams and plain indices inside its own namespace (verified: auto-creating
  `logs-newtest-greencircle` returned `201`, creating `grc-plain-new` returned `200`).
- Read and manage its own detection alerts.
- **Read** the shared Default space: dashboards, the full prebuilt detection-rule set
  (2,062 rules) and other shared saved objects.
- **Read** the shared Default alerts (the cross-tenant alert view), without being
  able to acknowledge, close, or modify them.

## What a tenant cannot do

- See, open, or write to the other tenant's space.
- Read or write another tenant's indices or data streams.
- Read the other tenant's alert indices.
- Acknowledge, close, or write the shared Default alerts.
- Create, edit or delete anything in the Default space (read-only; `403` verified).
- Read cluster health, security users/roles, or manage indices.
- Create an index outside its own namespace.

## Known limitations

| Limitation | Impact / mitigation |
|------------|---------------------|
| Single shared cluster and node | No resource isolation between tenants; a noisy tenant can affect others. Mitigate with per-tenant ILM, shard limits, and monitoring. |
| Basic license | Some advanced security features (e.g., certain rule actions, advanced DLS/FLS workflows) are unavailable. |
| No ingest-time `tenant` field | Prevents document-level tenancy; namespace isolation is the current control. |
| Detection rules and alerts are space-scoped | Rules are installed and enabled in `default`, `grcico-com` and `tkt-org` (2,062 each). Alerts land in the alert index of the space where the rule lives. The Default global rule set provides the shared cross-tenant alert view. |
| Enabled ≠ healthy | Many rules report `partial failure`/`failed` because the expected integration/index is absent, or because a tenant-scoped rule API key cannot read indices outside the tenant namespace. This is expected isolation behavior. |
| Scheduler load | 6,186 enabled rule instances on one node (2,062 × 3 spaces); rules are staggered and some show `never` until their first scheduled run. |
| Prebuilt package upgrades | Kibana can auto-install a newer `security_detection_engine` package (this happened during this work: 8.19.36 → 8.19.37). The upgrade removed the tenant-space rule copies. Re-run `tools/dr_sync_space.sh <space> <user:pass>` for both tenant spaces after any package change; see [10-detection-rules.md](10-detection-rules.md). |
| Fleet policies share one Fleet Server | Agent enrollment must be kept per-tenant via policy namespaces. |
| Kibana `space_all` | Tenants are space admins inside their own space, which is required for full read/write of saved objects. `space_read` on Default cannot write. |
