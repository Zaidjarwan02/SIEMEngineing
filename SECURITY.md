# Security Policy

## Scope

This repository is a **lab / reference implementation** of a multi-tenant SIEM.
It is not production-hardened and it intentionally documents a simplified lab
setup (plain HTTP on a private network, Basic license, single node).

## Secrets

No real credentials, API keys, tokens, or encryption keys are published here.
The credential file contains placeholders only. Before deploying:

1. Generate unique, strong passwords for every account.
2. Store the Kibana encryption keys in a secret manager.
3. Move `kibana_system` into the Kibana keystore.
4. Enable TLS for Elasticsearch and Kibana.
5. Move SSH to key-only authentication.
6. Rotate every credential used during testing.

## Reporting a vulnerability

If you find a security issue in the scripts or documentation, open a private
security advisory on GitHub (Repository → Security → Advisories) rather than a
public issue. Include:

- the affected file or step;
- what an attacker could do;
- the minimum reproduction;
- a suggested fix, if you have one.

## Known lab limitations

- Cluster health is yellow by design (single node, unassigned replicas).
- Many detection rules report warnings/failures because their integration is not
  installed or because tenant-scoped API keys cannot read other tenants' data.
- The Basic license skips 95 of the 2,157 packaged rules.
- The shared Default space is read-only for tenants; this is enforced by the
  role, not by the UI alone.
