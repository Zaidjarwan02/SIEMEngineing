# 02 — Baseline Before Changes

This is the state of the SIEM **before** tenant accounts were provisioned. Raw evidence:
[`evidence/02-elastic-discovery.txt`](evidence/02-elastic-discovery.txt),
[`evidence/03-roles-spaces-baseline.txt`](evidence/03-roles-spaces-baseline.txt),
[`evidence/04-fleet-detection-baseline.txt`](evidence/04-fleet-detection-baseline.txt).

## What already existed

### Kibana spaces

| Space ID | Display name | Notes |
|----------|--------------|-------|
| `default` | Default | Built-in space, reserved |
| `greencircle` | Tenant 1 | greencircle tenant space |
| `tkt` | Tenant 2 | TKT tenant space |

### Elasticsearch roles

Both tenant roles existed but were **dangerously broad**:

```json
{
  "greencircle": {
    "cluster": [],
    "indices": [
      { "names": ["logs-*", "metrics-*"], "privileges": ["all"], "allow_restricted_indices": false }
    ],
    "applications": [
      { "application": "kibana-.kibana", "privileges": ["space_all"], "resources": ["space:greencircle"] }
    ]
  },
  "tkt": {
    "cluster": [],
    "indices": [
      { "names": ["logs-*", "metrics-*"], "privileges": ["all"], "allow_restricted_indices": false }
    ],
    "applications": [
      { "application": "kibana-.kibana", "privileges": ["space_all"], "resources": ["space:tkt"] }
    ]
  }
}
```

`logs-*` and `metrics-*` match **every tenant's** data. Any user with either role could
read and write the other tenant's logs and metrics through the Elasticsearch API, even
though the Kibana UI was space-scoped.

### Users

No tenant users existed. The only users were the built-in service accounts
(`elastic`, `kibana`, `kibana_system`, `logstash_system`, `beats_system`, `apm_system`,
`remote_monitoring_user`). The two tenant roles had no members.

### Fleet

| Agent policy | Namespace | Agents |
|--------------|-----------|--------|
| `greencircle` | `greencircle` | 1 (`GC-LD-002`, offline) |
| `tkt` | `tkt` | 0 |
| `Agent policy 1` | `default` | 0 |

Fleet Server was configured at `https://192.168.1.212:8220`, but port 8220 was closed
during the audit.

### Data

Cluster health was green, but **only internal/system indices existed** — no tenant log
or metric data had been ingested yet. 48 active shards, all system-owned.

## Problems identified

| # | Problem | Impact |
|---|---------|--------|
| 1 | Tenant roles granted `all` on `logs-*` and `metrics-*` | **Cross-tenant data leak** via direct Elasticsearch API |
| 2 | No tenant users existed | Tenants could not log in |
| 3 | No tenant-scoped data views; only global `logs-*` / `metrics-*` patterns | Confusing UI; a tenant could point a data view at another tenant's data |
| 4 | Kibana encryption keys were missing (`xpack.encryptedSavedObjects.encryptionKey`, `xpack.reporting.encryptionKey`, `xpack.security.encryptionKey`) | Detection engine returned errors; alerting/task manager went critical; reports could not be generated |
| 5 | Elasticsearch HTTP TLS disabled | Credentials and data travel in cleartext on the LAN |
| 6 | UFW inactive; ES/Kibana bound to `0.0.0.0` | Full stack exposed to the whole LAN |
| 7 | `kibana_system` password stored in plaintext in `/etc/kibana/kibana.yml` | Credential exposure if the file is read |
| 8 | `cluster.initial_master_nodes: ["ubuntu"]` on a node named `node-1` | Stale bootstrap setting; can confuse future node joins |
| 9 | No swap, memory ~92–97% used | Risk of OOM kills under load |

## What "good" looked like after the work

- One user per tenant, each bound to exactly one role and one space.
- Each role scoped to that tenant's index/data-stream namespace only.
- No wildcard privilege that spans tenants.
- Kibana space isolation verified through the real login flow.
- Kibana encryption keys present, detection engine healthy.
- All of the above proven by an automated 40-check suite.
