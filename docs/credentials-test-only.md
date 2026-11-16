# Test Credentials — PLACEHOLDERS ONLY

> **No real credentials are published in this repository.**
>
> The values below are placeholders. Replace them locally and never commit a filled-in
> copy. The original lab credentials were removed before this repository was made public.

## Tenant users (Kibana)

| Tenant | Username | Password | Space |
|--------|----------|----------|-------|
| Tenant 1 (`greencircle`) | `T1_user` | `<TENANT1_PASSWORD>` | `greencircle` |
| Tenant 2 (`TKT`) | `T2_user` | `<TENANT2_PASSWORD>` | `tkt` |

## Elasticsearch / Kibana administration

| Account | Password | Notes |
|---------|----------|-------|
| `elastic` (superuser) | `<ADMIN_PASSWORD>` | Full cluster administration; use only for setup |
| `kibana_system` | `<KIBANA_SYSTEM_PASSWORD>` | Kibana → Elasticsearch service account; store in the Kibana keystore |

## VM operating system

| Account | Password | Notes |
|---------|----------|-------|
| `<SSH_USER>` (sudo) | `<SSH_PASSWORD>` | SSH login; use key-only auth outside the lab |

## Kibana encryption keys

The three Kibana encryption keys live in `/etc/kibana/kibana.yml`:

- `xpack.encryptedSavedObjects.encryptionKey`
- `xpack.reporting.encryptionKey`
- `xpack.security.encryptionKey`

They are **not** reproduced here. Back them up to a secret store; losing them makes
encrypted saved objects (alert rules, connectors, reports) unreadable.

## Endpoints

| Service | URL |
|---------|-----|
| Kibana | `http://<ELASTIC_HOST>:5601` |
| Elasticsearch | `http://<ELASTIC_HOST>:9200` |

## Rotation checklist

- [ ] Rotate the tenant user passwords.
- [ ] Rotate the `elastic` superuser password and stop using it for automation.
- [ ] Rotate `kibana_system` and move it into the Kibana keystore.
- [ ] Move SSH to key-only authentication.
- [ ] Back up the Kibana encryption keys to a secret manager.
- [ ] Remove every local `.env` file and filled-in credential file before sharing.
