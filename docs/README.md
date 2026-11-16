# Elastic MSSP — Multi-Tenant SIEM on Elasticsearch / Kibana

**Environment:** test VM `192.168.1.212` (Ubuntu 26.04.1 LTS, VirtualBox)
**Stack:** Elasticsearch 8.19.24 + Kibana 8.19.24, Basic license
**Cluster:** `greencircle.SIEM`
**Status:** Tenant isolation implemented and verified — **53 / 53 isolation checks** and **15 / 15 detection-rule checks** pass. All 2,062 prebuilt detection rules are enabled in each of the three spaces.
**Last verified:** 2026-11-12

---

## What this documentation covers

This folder documents the complete state of the test SIEM, the multi-tenant design,
how the tenants were provisioned, the evidence that they are isolated, and the
security gaps that still need attention before this could be considered production-ready.

| # | Document | Purpose |
|---|----------|---------|
| 01 | [Inventory](01-inventory.md) | Hardware, OS, network, services, ports, versions |
| 02 | [Baseline before changes](02-baseline-before-changes.md) | What existed before this work and what was wrong |
| 03 | [Tenant design](03-tenant-design.md) | Isolation architecture and the reasoning behind it |
| 04 | [Provisioning runbook](04-provisioning-runbook.md) | How to create, change, or remove a tenant |
| 05 | [Verification evidence](05-verification-evidence.md) | 53/53 isolation tests, 15/15 rule tests and login-flow results |
| 06 | [Operations guide](06-operations-guide.md) | How tenants log in and use the SIEM day to day |
| 07 | [Hardening checklist](07-hardening-checklist.md) | Open security findings and remediation steps |
| 08 | [Change log](08-change-log.md) | Every change made to the machine, in order |
| 09 | [Raw evidence index](09-raw-evidence-index.md) | Index of captured raw command output |
| 10 | [Detection rules](10-detection-rules.md) | Prebuilt `elastic/detection-rules` install, enablement, placement, and recovery |
| 11 | [Add a new tenant](11-add-new-tenant.md) | Step-by-step new-tenant provisioning with identical permissions |
| — | [Test credentials](credentials-test-only.md) | **Test-only** accounts and passwords (do not use in production) |

---

## Tenants at a glance

| Tenant | Kibana Space | Data namespace | Role | User |
|--------|--------------|----------------|------|------|
| Tenant 1 (`greencircle`) | `greencircle` | `logs-*-greencircle*`, `metrics-*-greencircle*`, `traces-*-greencircle*`, `synthetics-*-greencircle*`, `profiling-*-greencircle*`, `greencircle-*` | `greencircle` | `T1_user` |
| Tenant 2 (`TKT`) | `tkt` | `logs-*-tkt*`, `metrics-*-tkt*`, `traces-*-tkt*`, `synthetics-*-tkt*`, `profiling-*-tkt*`, `tkt-*` | `tkt` | `T2_user` |

Each tenant user has **full read/write inside its own namespace** and **no visibility of the
other tenant** — verified at both the Elasticsearch data layer and the Kibana UI layer.

### Shared Default space

Both tenants also have **read-only** access to the Default space (`space_read`), which acts
as the shared "general" area: shared dashboards and the full prebuilt detection-rule set
(2,062 rules) are visible to everyone, but only the administrator can change them. Tenant
writes to Default return `403`.

### Detection rules

The official `security_detection_engine` package (the packaged form of
`github.com/elastic/detection-rules`) is installed as **2,062 rules in each of the three
spaces, all enabled**. The Default space's global copy provides the shared cross-tenant
alert view; the tenant-space copies are scoped to each tenant's data. See
[10-detection-rules.md](10-detection-rules.md).

---

## Key URLs

| Service | URL |
|---------|-----|
| Kibana | http://192.168.1.212:5601 |
| Elasticsearch | http://192.168.1.212:9200 |

> HTTP TLS is currently **disabled** on Elasticsearch (see [hardening](07-hardening-checklist.md)).

---

## Reproducing the verification

From the Windows workstation in `D:\elasticMSSP`:

```powershell
$env:PYTHONIOENCODING="utf-8"
python tools\remote_exec.py tools\verify_isolation_final.sh /tmp/verify_isolation_final.sh "bash /tmp/verify_isolation_final.sh"
python tools\remote_exec.py tools\dr_verify_isolation.sh /tmp/dr_verify_isolation.sh "bash /tmp/dr_verify_isolation.sh"
python tools\remote_exec.py tools\verify_login.sh /tmp/verify_login.sh "bash /tmp/verify_login.sh"
```

Expected results: `PASS=53 FAIL=0`, `PASS=15 FAIL=0`, and login checks matching
[05-verification-evidence.md](05-verification-evidence.md).
