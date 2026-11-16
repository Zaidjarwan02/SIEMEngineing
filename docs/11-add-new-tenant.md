# 11 — Add a New Tenant (Step by Step)

This is the exact procedure to add a new tenant with the **same permissions and
isolation** as the existing tenants.

The lab currently uses these names; the same pattern works for any new tenant:

| Screenshot label | Kibana space | Data namespace | Role | User |
|------------------|--------------|----------------|------|------|
| **All Tenant** | `default` | *(shared, read-only)* | — | every tenant |
| **Tenant 1** | `greencircle` | `greencircle` | `greencircle` | `greencircle_user` |
| **Tenant 2** | `tkt` | `tkt` | `tkt` | `tkt_user` |
| *new tenant* | `<SPACE_ID>` | `<NAMESPACE>` | `<ROLE_NAME>` | `<USERNAME>` |

---

## 0. Before you start

You need:

- the Elastic superuser (`elastic`) or an equivalent administrator;
- the Kibana URL (`http://<ELASTIC_HOST>:5601`) and Elasticsearch URL
  (`http://<ELASTIC_HOST>:9200`);
- a decision for the four identifiers in the table above.

### Naming rules (important)

| Identifier | Rule | Example |
|------------|------|---------|
| `SPACE_ID` | lowercase letters, digits, `-`; used in the alert index name | `acme` |
| `NAMESPACE` | suffix used by Fleet/data streams | `acme` |
| `ROLE_NAME` | Elasticsearch role name | `Acme` |
| `USERNAME` | Kibana/Elasticsearch login | `acme_user` |

Detection alerts are stored in:

```
.alerts-security.alerts-<SPACE_ID>*
.internal.alerts-security.alerts-<SPACE_ID>*
```

The data streams must be named:

```
logs-<dataset>-<NAMESPACE>
metrics-<dataset>-<NAMESPACE>
traces-<dataset>-<NAMESPACE>
synthetics-<dataset>-<NAMESPACE>
profiling-<dataset>-<NAMESPACE>
```

If the namespace is `acme`, the tenant can read/write `logs-*-acme*` etc. and
nothing outside that namespace.

Set shell variables to keep the commands short:

```bash
ES="http://<ELASTIC_HOST>:9200"
KB="http://<ELASTIC_HOST>:5601"
ADMIN='elastic:<ADMIN_PASSWORD>'
SPACE='acme'
NS='acme'
ROLE='Acme'
USER='acme_user'
PASS='<NEW_TENANT_PASSWORD>'
X='kbn-xsrf: true'
J='Content-Type: application/json'
```

---

## 1. Create the Kibana space

```bash
curl -s -u "$ADMIN" -H "$X" -H "$J" -X POST "$KB/api/spaces/space" -d "{
  \"id\": \"$SPACE\",
  \"name\": \"<DISPLAY_NAME>\",
  \"description\": \"Tenant space for <DISPLAY_NAME>\",
  \"initials\": \"AC\",
  \"color\": \"#9170B8\",
  \"disabledFeatures\": []
}"
```

Expected: `200` with the created space object. The space is empty at this point.

---

## 2. Create the role

The role is the **only** place that defines what the tenant can reach. It grants:

1. full read/write on the tenant's own data namespace;
2. full read/write on the tenant's own alert indices;
3. **read-only** access to the shared Default alert indices (so the tenant can
   see the cross-tenant alert view in the Default space);
4. `space_all` on exactly its own space;
5. `space_read` on the shared `default` space.

Save this as `role.json` and replace `<SPACE_ID>` and `<NAMESPACE>`:

```json
{
  "cluster": [],
  "indices": [
    {
      "names": [
        "logs-*-<NAMESPACE>*",
        "metrics-*-<NAMESPACE>*",
        "traces-*-<NAMESPACE>*",
        "synthetics-*-<NAMESPACE>*",
        "profiling-*-<NAMESPACE>*"
      ],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": ["<NAMESPACE>-*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": [
        ".alerts-security.alerts-<SPACE_ID>*",
        ".internal.alerts-security.alerts-<SPACE_ID>*"
      ],
      "privileges": ["all"],
      "allow_restricted_indices": true
    },
    {
      "names": [
        ".alerts-security.alerts-default*",
        ".internal.alerts-security.alerts-default*"
      ],
      "privileges": ["read", "view_index_metadata"],
      "allow_restricted_indices": true
    }
  ],
  "applications": [
    {
      "application": "kibana-.kibana",
      "privileges": ["space_all"],
      "resources": ["space:<SPACE_ID>"]
    },
    {
      "application": "kibana-.kibana",
      "privileges": ["space_read"],
      "resources": ["space:default"]
    }
  ],
  "description": "<DISPLAY_NAME> tenant: full read/write on its namespace and alert indices; read-only in the shared Default space and its alerts."
}
```

Apply it:

```bash
curl -s -u "$ADMIN" -H "$J" -X PUT "$ES/_security/role/$ROLE" -d @role.json
```

Expected: `{"role":{"created":true}}` (or `"created":false` if updating).

> **Do not grant cluster privileges.** The tenant must not read cluster health,
> security users, or create indices outside its namespace.

---

## 3. Create the user

```bash
curl -s -u "$ADMIN" -H "$J" -X POST "$ES/_security/user/$USER" -d "{
  \"password\": \"$PASS\",
  \"roles\": [\"$ROLE\"],
  \"metadata\": { \"tenant\": \"$NS\" }
}"
```

Expected: `{"created":true}`.

Verify the role is attached:

```bash
curl -s -u "$ADMIN" "$ES/_security/user/$USER"
```

---

## 4. Create the tenant data views

Create these **inside the new space**. Use the tenant user so the saved objects
belong to the tenant space (the administrator can also create them).

```bash
for pair in \
  "logs-*-${NS}*|<DISPLAY_NAME> Logs" \
  "metrics-*-${NS}*|<DISPLAY_NAME> Metrics" \
  "${NS}-*|<DISPLAY_NAME> Custom"; do
  TITLE="${pair%%|*}"
  NAME="${pair##*|}"
  curl -s -u "$USER:$PASS" -H "$X" -H "$J" \
    -X POST "$KB/s/$SPACE/api/data_views/data_view" -d "{
      \"data_view\": {
        \"title\": \"$TITLE\",
        \"name\": \"$NAME\",
        \"timeFieldName\": \"@timestamp\"
      },
      \"override\": true
    }"
  echo
done
```

Expected: three `200` responses. Do **not** create broad `logs-*` or `metrics-*`
data views in the tenant space.

---

## 5. Install the prebuilt detection rules

Install the rules **as the new tenant user**, not as `elastic`. This is what
scopes every rule's API key to the tenant role, so the rule can never read
another tenant's data.

```bash
# 5a. Check the package status
curl -s -u "$USER:$PASS" -H "$X" \
  "$KB/s/$SPACE/internal/detection_engine/prebuilt_rules/status"

# 5b. Install every rule the license allows (mode ALL_RULES, not ALL)
curl -s -u "$USER:$PASS" -H "$X" -H "$J" \
  -X POST "$KB/s/$SPACE/internal/detection_engine/prebuilt_rules/installation/_perform" \
  -d '{"mode":"ALL_RULES"}'

# 5c. Upgrade any outdated rules
curl -s -u "$USER:$PASS" -H "$X" -H "$J" \
  -X POST "$KB/s/$SPACE/internal/detection_engine/prebuilt_rules/upgrade/_perform" \
  -d '{"mode":"ALL_RULES"}'
```

A fresh install of ~2,062 rules takes about **2 minutes**. The package is
`security_detection_engine` (currently **8.19.37** on the lab); 2,157 rules are
packaged and 2,062 are installable on the Basic license.

---

## 6. Enable every rule

Kibana caps a single bulk action at **100 rule ids**. Use the helper script; it
fetches only the disabled rules and enables them 100 at a time.

```bash
python tools/enable_all_rules_http.py "$SPACE" --user "$USER" --password "$PASS"
```

Expected output ends with:

```
=== DONE acme: enabled=2062 batch_failed=0 elapsed=... ===
```

If you prefer raw API calls, the loop is:

```bash
# fetch all disabled rule internal ids, then send them in chunks of 100
curl -s -u "$USER:$PASS" -H "$X" \
  "$KB/s/$SPACE/api/detection_engine/rules/_find?per_page=1000&page=1&filter=alert.attributes.enabled:false"

# for each chunk of <=100 ids:
curl -s -u "$USER:$PASS" -H "$X" -H "$J" \
  -X POST "$KB/s/$SPACE/api/detection_engine/rules/_bulk_action" \
  -d '{"action":"enable","ids":["<id1>","<id2>", "..."]}'
```

> Do not send more than 100 ids: Kibana returns
> `"More than 100 ids sent for bulk edit action."` and the batch is rejected.

---

## 7. Make the Default space show the new tenant's alerts

The Default space is the **shared, read-only** alert view. Two things make it
work:

1. The Default space has its own copy of the **global** rule set, installed and
   enabled by `elastic`. Those rules have global API keys, so they can read every
   tenant's data. They write alerts to the Default alert index
   (`.alerts-security.alerts-default*`).
2. The new tenant's role has **read** on the Default alert indices (step 2), so
   the tenant can open **Security → Alerts** in Default and see those alerts.
   The tenant cannot acknowledge, close, or edit them (`403`).

The global rules match standard data-stream names such as
`logs-aws.cloudtrail-*`, `logs-endpoint.events.process-*`, and `logs-*`. As long
as the new tenant's Fleet integration writes to
`logs-<dataset>-<NAMESPACE>` (the normal Fleet naming), the Default rules cover
it automatically.

If the new tenant uses a **non-standard index name**, add a Default-space rule
(or edit an existing one) whose index pattern includes that name. Do not grant
the tenant direct read access to another tenant's alert index; keep the shared
view in Default.

---

## 8. Verify the new tenant

### 8.1 Login and space visibility

```bash
# Real Kibana login
curl -s -c /tmp/cookies -H "$J" -X POST "$KB/internal/security/login" \
  -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}"

# Should list default + the new space only
curl -s -b /tmp/cookies -H "$X" "$KB/api/spaces/space"
```

Expected: `default` and `<SPACE_ID>`; the other tenants' spaces are absent.

### 8.2 Data isolation

```bash
# Own namespace: 200 read / 201 write
curl -s -o /dev/null -w '%{http_code}\n' -u "$USER:$PASS" "$ES/logs-*-${NS}*/_search"
curl -s -o /dev/null -w '%{http_code}\n' -u "$USER:$PASS" -H "$J" \
  -X POST "$ES/logs-test-${NS}/_doc?refresh=true" \
  -d "{\"@timestamp\":\"$(date -u +%FT%TZ)\",\"message\":\"tenant onboarding test\"}"

# Another tenant's namespace: 0 hits on a wildcard, 403 on a named index
curl -s -u "$USER:$PASS" "$ES/logs-*-greencircle*/_search"
curl -s -o /dev/null -w '%{http_code}\n' -u "$USER:$PASS" \
  "$ES/.internal.alerts-security.alerts-greencircle-000001/_search"
```

Expected: own read `200`, own write `201`; foreign wildcard `0` hits; named
foreign alert index `403`.

### 8.3 Default space and Default alerts

```bash
# Default space is readable, but not writable
curl -s -o /dev/null -w '%{http_code}\n' -u "$USER:$PASS" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard"
curl -s -o /dev/null -w '%{http_code}\n' -u "$USER:$PASS" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/saved_objects/dashboard" -d '{"attributes":{"title":"forbidden"}}'

# Default alerts: readable, not writable
curl -s -o /dev/null -w '%{http_code}\n' -u "$USER:$PASS" "$ES/.internal.alerts-security.alerts-default-000001/_search"
curl -s -o /dev/null -w '%{http_code}\n' -u "$USER:$PASS" -H "$J" \
  -X POST "$ES/.alerts-security.alerts-default/_doc" -d '{"test":1}'
```

Expected: Default read `200`, Default write `403`, Default alert read `200`,
Default alert write `403`.

### 8.4 Rule counts

```bash
curl -s -u "$USER:$PASS" -H "$X" \
  "$KB/s/$SPACE/api/detection_engine/rules/_find?per_page=1"
curl -s -u "$USER:$PASS" -H "$X" \
  "$KB/s/$SPACE/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true"
```

Expected: total `2062`, enabled `2062` (for the current package).

### 8.5 Run the full suites

```bash
python tools/remote_exec.py tools/verify_isolation_final.sh /tmp/verify.sh "bash /tmp/verify.sh"
python tools/remote_exec.py tools/dr_verify_isolation.sh /tmp/dr_verify.sh "bash /tmp/dr_verify.sh"
python tools/remote_exec.py tools/verify_login.sh /tmp/login.sh "bash /tmp/login.sh"
```

Expected on the lab: `PASS=53 FAIL=0`, `PASS=15 FAIL=0`, and the login checks.

---

## 9. Record the tenant

Add the new tenant to:

- the tenant table in `docs/README.md` and the root `README.md`;
- `docs/03-tenant-design.md` (role mapping);
- the sanitized credentials template (`docs/credentials-test-only.md` uses
  placeholders in the public repo);
- the change log (`docs/08-change-log.md`).

---

## 10. Maintenance

| Event | Action |
|-------|--------|
| Kibana or `security_detection_engine` upgrade | Re-run the install/upgrade in step 5, then enable in step 6. Package upgrades can remove tenant-space rule copies. |
| New tenant added | Repeat this document. Do not copy data or saved objects between tenant spaces. |
| New data source for a tenant | Enroll the agent with the tenant's namespace; do not use another tenant's namespace. |
| Alert volume too high | Disable noisy rules in that tenant's space only, or tune their index patterns. Do not disable the shared Default rule set without checking the cross-tenant view. |
| Tenant leaves | Delete the user, role, space, data streams, and alert indices after exporting anything that must be retained. |

---

## Appendix A — Remove a tenant

```bash
# 1. Disable/delete the user
curl -s -u "$ADMIN" -X DELETE "$ES/_security/user/$USER"

# 2. Delete the role
curl -s -u "$ADMIN" -X DELETE "$ES/_security/role/$ROLE"

# 3. Delete the Kibana space (this removes its saved objects)
curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/api/spaces/space/$SPACE"

# 4. Delete the tenant data streams and alert indices (irreversible)
curl -s -u "$ADMIN" -X DELETE "$ES/_data_stream/logs-*-${NS}"
curl -s -u "$ADMIN" -X DELETE "$ES/_data_stream/metrics-*-${NS}"
curl -s -u "$ADMIN" -X DELETE "$ES/.internal.alerts-security.alerts-${SPACE}*"
```

Always confirm the exact names before deleting. Deletion is not reversible.

---

## Appendix B — Common errors

| Symptom | Cause | Fix |
|---------|-------|-----|
| `403` on the new space | Missing `space_all` on `space:<SPACE_ID>` | Fix the role, re-login |
| `403` creating a data view | Space privilege missing or wrong space in URL | Use `/s/<SPACE_ID>/...` |
| Rule install returns `0` rules | Package not installed or license blocks it | Check `/api/fleet/epm/packages/security_detection_engine` and the prebuilt status |
| Bulk enable returns `400` | More than 100 ids in one request | Chunk into 100 |
| Tenant cannot see Default alerts | Role lacks read on `.alerts-security.alerts-default*` | Add the read block from step 2 |
| Tenant rules show `partial failure` | Rule API key is tenant-scoped; the prebuilt pattern includes indices outside the tenant namespace | Expected. The rule only sees the tenant's own data; the Default global rule set provides the cross-tenant view |
| Default alerts page empty | No Default rules have run yet, or no matching data | Check rule execution in Default; ensure data uses standard `logs-<dataset>-<NAMESPACE>` names |

---

## Appendix C — Why the tenant rule copies are scoped

A detection rule runs with an API key derived from the user who enabled it. The
tenant-space rules are enabled by `greencircle_user` / `tkt_user`, so their API keys can
only read that tenant's namespace. This is deliberate: a tenant editing one of
its own rules cannot make it query another tenant's data. The trade-off is that
many prebuilt rules report `partial failure` because their index patterns
include datasets the tenant is not allowed to read. That is an isolation
success, not a data leak. The shared Default rule set (enabled by `elastic`)
provides the cross-tenant alert view.
