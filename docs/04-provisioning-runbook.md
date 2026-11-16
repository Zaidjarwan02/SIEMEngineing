# 04 — Tenant Provisioning Runbook

This runbook reproduces the tenant setup and shows how to add, change, or remove a tenant.
All commands run **on the VM** (or via `tools/remote_exec.py`) as a user with `sudo`, using
the `elastic` superuser for the API calls.

## Prerequisites

| Item | Value |
|------|-------|
| Kibana | `http://127.0.0.1:5601` (or `http://192.168.1.212:5601`) |
| Elasticsearch | `http://127.0.0.1:9200` |
| Superuser | `elastic` (password in [`credentials-test-only.md`](credentials-test-only.md)) |
| Kibana encryption keys | Must be present in `/etc/kibana/kibana.yml` |
| Fleet namespace | Must match the tenant namespace used in the index patterns |

> The scripts below were used as-is on the test VM. They are idempotent: re-running them
> updates roles/users/data views rather than duplicating them.

## Step 0 — Confirm Kibana is healthy

```bash
curl -s http://127.0.0.1:5601/api/status | python3 -c \
  "import sys,json;print(json.load(sys.stdin)['status']['overall']['level'])"
# expected: available
```

If the encryption keys are missing, run `tools/fix_kibana_keys.sh` first (it appends
random keys to `/etc/kibana/kibana.yml` and restarts Kibana).

## Step 1 — Define the tenant

Decide these four values **before** creating anything:

| Field | Example (greencircle) | Rule |
|-------|-----------------------|------|
| Space ID | `greencircle` | Must already exist (or create it) |
| Data namespace | `greencircle` | Used as the suffix of Fleet data streams (`logs-<dataset>-greencircle`) |
| Role name | `greencircle` | |
| Username | `greencircle_user` | |

> The data namespace must be the **last segment** of every data-stream name. Fleet writes
> `logs-<dataset>-<namespace>` and `metrics-<dataset>-<namespace>`, so the role pattern
> `logs-*-<namespace>*` catches all of them.

## Step 2 — Create or confirm the Kibana space

```bash
KB=http://127.0.0.1:5601
U='elastic:<password>'

curl -s -u "$U" -H 'kbn-xsrf: true' "$KB/api/spaces/space"   # list
```

Create it only if missing:

```bash
curl -s -u "$U" -H 'Content-Type: application/json' -H 'kbn-xsrf: true' \
  -X POST "$KB/api/spaces/space" \
  -d '{"id":"NEW-SPACE","name":"New Tenant","description":"","initials":"nt","color":"#9170B8","disabledFeatures":[]}'
```

## Step 3 — Create the role

The role must contain **only** that tenant's namespaces. Do not use `logs-*` or `metrics-*`
without a tenant suffix.

```bash
ES=http://127.0.0.1:9200
U='elastic:<password>'
NS='newtenant'
SPACE='new-space'

cat > /tmp/role_${NS}.json <<EOF
{
  "cluster": [],
  "indices": [
    {
      "names": ["logs-*-${NS}*", "metrics-*-${NS}*", "traces-*-${NS}*",
                "synthetics-*-${NS}*", "profiling-*-${NS}*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": ["${NS}-*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": [".alerts-security.alerts-${SPACE}*", ".internal.alerts-security.alerts-${SPACE}*"],
      "privileges": ["all"],
      "allow_restricted_indices": true
    }
  ],
  "applications": [
    { "application": "kibana-.kibana", "privileges": ["space_all"],  "resources": ["space:${SPACE}"] },
    { "application": "kibana-.kibana", "privileges": ["space_read"], "resources": ["space:default"] }
  ],
  "description": "${NS} tenant: full read/write on its own namespace; full UI in space ${SPACE}; read-only in shared Default space."
}
EOF

curl -s -u "$U" -H 'Content-Type: application/json' \
  -X PUT "$ES/_security/role/${NS}" -d @/tmp/role_${NS}.json
```

> **Why `space_read` on `space:default`?** Default is the shared general space for all
> tenants: they can read shared dashboards and the shared prebuilt detection-rule set, but
> cannot create, edit or delete anything there. Own-space `space_all` is unchanged. If the
> organization does not want a shared space, remove that second application entry and
> tenants will see only their own space.

> **Never build this JSON by re-posting a `GET /_security/role/<name>` response.** That
> endpoint wraps the role as `{"<name>": {...}}`; feeding the wrapper back into `PUT`
> silently creates an empty role. Use static JSON as shown, or
> `tools/restore_roles_default_shared.sh` for the existing tenants.

## Step 4 — Create the user

```bash
cat > /tmp/user_${NS}.json <<EOF
{
  "password": "REPLACE_WITH_STRONG_PASSWORD",
  "roles": ["${NS}"],
  "full_name": "New Tenant User",
  "email": "newtenant@example.local",
  "metadata": {"tenant": "${NS}", "managed_by": "mssp-provisioning"}
}
EOF

curl -s -u "$U" -H 'Content-Type: application/json' \
  -X PUT "$ES/_security/user/${NS}_user" -d @/tmp/user_${NS}.json
```

## Step 5 — Create the per-space data views

```bash
KB=http://127.0.0.1:5601
U='elastic:<password>'

mkview() {
  space="$1"; title="$2"; name="$3"
  curl -s -u "$U" -H 'Content-Type: application/json' -H 'kbn-xsrf: true' \
    -X POST "$KB/s/$space/api/data_views/data_view" \
    -d "{\"data_view\":{\"title\":\"$title\",\"name\":\"$name\",\"timeFieldName\":\"@timestamp\"}}"
}

mkview new-space 'logs-*-newtenant*'    'New Tenant Logs'
mkview new-space 'metrics-*-newtenant*' 'New Tenant Metrics'
mkview new-space 'newtenant-*'          'New Tenant Custom'
```

## Step 6 — Create the Fleet policy / enrollment

Fleet writes into `logs-<dataset>-<namespace>` and `metrics-<dataset>-<namespace>`. Create
the agent policy with the **same namespace**:

```bash
curl -s -u "$U" -H 'Content-Type: application/json' -H 'kbn-xsrf: true' \
  -X POST "$KB/api/fleet/agent_policies" \
  -d '{"name":"newtenant","namespace":"newtenant","description":"New tenant policy"}'
```

Then enroll agents with that policy. Keep one policy per tenant.

## Step 7 — Install and enable prebuilt detection rules in the tenant space

Install the rules **as the tenant user** so every rule's API key is scoped to that
tenant's role and cannot query other tenants' data:

```bash
curl -s -u 'newtenant_user:PASSWORD' -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KB/s/new-space/internal/detection_engine/prebuilt_rules/installation/_perform" \
  -d '{"mode":"ALL_RULES"}'
```

On the Basic license this installs 2,062 of the 2,157 packaged rules (the rest require a
higher license). Then **enable every rule** in batches of 100:

```bash
python tools/enable_all_rules_http.py new-space --user newtenant_user --password PASSWORD
```

Kibana rejects more than 100 ids in one bulk action. The helper fetches only disabled
rules and sends 20–21 batches; a full space takes about 2–3 minutes.

A fresh install takes about two minutes. See [10-detection-rules.md](10-detection-rules.md)
for the full procedure, the package auto-upgrade hazard, and recovery. For a complete
copy-paste new-tenant walkthrough (space, role, user, data views, rules, verification),
use [11-add-new-tenant.md](11-add-new-tenant.md).

## Step 8 — Verify

Run the automated suite (from the Windows workstation):

```powershell
$env:PYTHONIOENCODING="utf-8"
python tools\remote_exec.py tools\verify_isolation_final.sh /tmp/verify_isolation_final.sh "bash /tmp/verify_isolation_final.sh"
python tools\remote_exec.py tools\dr_verify_isolation.sh /tmp/dr_verify_isolation.sh "bash /tmp/dr_verify_isolation.sh"
python tools\remote_exec.py tools\verify_login.sh /tmp/verify_login.sh "bash /tmp/verify_login.sh"
```

Expected: `PASS=53 FAIL=0`, `PASS=15 FAIL=0`, and the login table in
[05-verification-evidence.md](05-verification-evidence.md).

For a single new tenant, at minimum check:

```bash
# login and space visibility
curl -s -u 'newtenant_user:PASSWORD' -H 'kbn-xsrf: true' "$KB/api/spaces/space"

# own data works
curl -s -o /dev/null -w '%{http_code}\n' -u 'newtenant_user:PASSWORD' \
  "$ES/logs-*-newtenant*/_search"        # 200

# other tenant blocked
curl -s -o /dev/null -w '%{http_code}\n' -u 'newtenant_user:PASSWORD' \
  "$ES/logs-*-greencircle*/_search"      # 200 with 0 hits, or 403
```

## Change a password

```bash
curl -s -u "$U" -H 'Content-Type: application/json' \
  -X POST "$ES/_security/user/greencircle_user/_password" \
  -d '{"password":"NEW_STRONG_PASSWORD"}'
```

Update the password in the tenant's password manager and in
[`credentials-test-only.md`](credentials-test-only.md) if this is still the test environment.

## Change a tenant's namespace or space

1. Create the new space (Step 2).
2. Update the role's index patterns and `resources` (Step 3).
3. Create the new data views (Step 5).
4. Re-run verification.
5. Delete the old data views and, once data is migrated, the old space.

Do **not** widen a role to `logs-*` / `metrics-*` as a shortcut.

## Remove a tenant

```bash
U='elastic:<password>'
ES=http://127.0.0.1:9200
KB=http://127.0.0.1:5601

# 1. disable the user (keeps an audit trail)
curl -s -u "$U" -H 'Content-Type: application/json' \
  -X PUT "$ES/_security/user/greencircle_user" -d '{"enabled":false}'

# 2. remove the role (after the user is disabled)
curl -s -u "$U" -X DELETE "$ES/_security/role/greencircle"

# 3. delete the space (this deletes its saved objects)
curl -s -u "$U" -H 'kbn-xsrf: true' -X DELETE "$KB/api/spaces/space/greencircle"

# 4. (optional, destructive) delete the tenant's data
curl -s -u "$U" -X DELETE "$ES/logs-*-greencircle*"
curl -s -u "$U" -X DELETE "$ES/metrics-*-greencircle*"
curl -s -u "$U" -X DELETE "$ES/greencircle-*"
```

Always take a snapshot before deleting data.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| User logs in but sees a 403 page | User has no access to the landing space | Confirm the role has `space_all` on `space:<space-id>`; `/` should redirect to `/spaces/space_selector` (with two accessible spaces) or `/s/<space>/spaces/enter` (with one) |
| 403 when saving in Default | Default is shared read-only (`space_read`) | Expected; make changes in the tenant's own space or as administrator |
| Endpoint Security rule re-enabled by itself | Package install/upgrade re-applies the immutable rule | Expected in the current all-enabled deployment; verify the enabled count is still 2,062 |
| Tenant space suddenly has 0 detection rules | Kibana auto-upgraded the `security_detection_engine` package | Re-run `tools/dr_sync_space.sh <space> <user:pass>` then `tools/enable_all_rules_http.py <space>`; see [10-detection-rules.md](10-detection-rules.md) |
| `403 index_not_found_exception` on own data | Index/data-stream does not exist yet | Expected until Fleet/agent writes data; create the Fleet policy with the right namespace |
| Detection engine 404 / task manager critical | Kibana encryption keys missing | Run `tools/fix_kibana_keys.sh` |
| Data view shows no data | Pattern does not match the namespace, or user lacks privilege | Check the data-stream name suffix and the role pattern |
| Fleet agent not enrolling | Fleet Server port 8220 closed / policy mismatch | Check `ss -tulpn` and the Fleet Server host setting |
