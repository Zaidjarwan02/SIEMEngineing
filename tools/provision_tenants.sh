#!/usr/bin/env bash
# Provision multi-tenant access for the Elastic MSSP test cluster.
#   Tenant 1: GreenCircle  -> space grcico-com, data namespace greencircle
#   Tenant 2: TKT          -> space tkt-org,    data namespace tkt
# Each tenant role gets full read/write ONLY on its own data namespace and
# full Kibana access ONLY inside its own space.
set -e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
U="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'

echo "### 1. Roles"

cat > /tmp/role_greencircle.json <<'EOF'
{
  "cluster": [],
  "indices": [
    {
      "names": [
        "logs-*-greencircle*",
        "metrics-*-greencircle*",
        "traces-*-greencircle*",
        "synthetics-*-greencircle*",
        "profiling-*-greencircle*"
      ],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": ["grc-*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": [
        ".alerts-security.alerts-grcico-com*",
        ".internal.alerts-security.alerts-grcico-com*"
      ],
      "privileges": ["all"],
      "allow_restricted_indices": true
    }
  ],
  "applications": [
    {
      "application": "kibana-.kibana",
      "privileges": ["space_all"],
      "resources": ["space:grcico-com"]
    }
  ],
  "description": "GreenCircle tenant: full read/write on greencircle data and grc-* only; UI access limited to space grcico-com."
}
EOF

cat > /tmp/role_tkt.json <<'EOF'
{
  "cluster": [],
  "indices": [
    {
      "names": [
        "logs-*-tkt*",
        "metrics-*-tkt*",
        "traces-*-tkt*",
        "synthetics-*-tkt*",
        "profiling-*-tkt*"
      ],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": ["tkt-*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": [
        ".alerts-security.alerts-tkt-org*",
        ".internal.alerts-security.alerts-tkt-org*"
      ],
      "privileges": ["all"],
      "allow_restricted_indices": true
    }
  ],
  "applications": [
    {
      "application": "kibana-.kibana",
      "privileges": ["space_all"],
      "resources": ["space:tkt-org"]
    }
  ],
  "description": "TKT tenant: full read/write on tkt data and tkt-* only; UI access limited to space tkt-org."
}
EOF

echo -n "GreenCircle: "; curl -s -u "$U" -H "$J" -X PUT "$ES/_security/role/GreenCircle" -d @/tmp/role_greencircle.json; echo
echo -n "tkt:         "; curl -s -u "$U" -H "$J" -X PUT "$ES/_security/role/tkt" -d @/tmp/role_tkt.json; echo

echo
echo "### 2. Users"

cat > /tmp/user_grc.json <<'EOF'
{
  "password": "<TENANT1_PASSWORD>",
  "roles": ["GreenCircle"],
  "full_name": "GreenCircle Tenant User",
  "email": "grc_user@greencircle.local",
  "metadata": {"tenant": "greencircle", "managed_by": "mssp-provisioning"}
}
EOF
cat > /tmp/user_tkt.json <<'EOF'
{
  "password": "<TENANT2_PASSWORD>",
  "roles": ["tkt"],
  "full_name": "TKT Tenant User",
  "email": "tkt_user@tkt.local",
  "metadata": {"tenant": "tkt", "managed_by": "mssp-provisioning"}
}
EOF

echo -n "grc_user: "; curl -s -u "$U" -H "$J" -X PUT "$ES/_security/user/grc_user" -d @/tmp/user_grc.json; echo
echo -n "tkt_user: "; curl -s -u "$U" -H "$J" -X PUT "$ES/_security/user/tkt_user" -d @/tmp/user_tkt.json; echo

echo
echo "### 3. Data views per space"

mkview() {
  space="$1"; title="$2"; name="$3"
  printf '%-14s %-28s -> ' "$space" "$name"
  curl -s -u "$U" -H "$J" -H "$X" -X POST "$KB/s/$space/api/data_views/data_view" \
    -d "{\"data_view\":{\"title\":\"$title\",\"name\":\"$name\",\"timeFieldName\":\"@timestamp\"}}" \
    | head -c 300
  echo
}

mkview grcico-com 'logs-*-greencircle*'   'GreenCircle Logs'
mkview grcico-com 'metrics-*-greencircle*' 'GreenCircle Metrics'
mkview grcico-com 'grc-*'                  'GreenCircle Custom (grc-*)'
mkview tkt-org    'logs-*-tkt*'            'TKT Logs'
mkview tkt-org    'metrics-*-tkt*'         'TKT Metrics'
mkview tkt-org    'tkt-*'                  'TKT Custom (tkt-*)'

echo
echo "### 4. Verify role definitions"
curl -s -u "$U" "$ES/_security/role/GreenCircle" | python3 -m json.tool
curl -s -u "$U" "$ES/_security/role/tkt" | python3 -m json.tool

echo
echo "### 5. Verify users"
curl -s -u "$U" "$ES/_security/user/grc_user" | python3 -m json.tool
curl -s -u "$U" "$ES/_security/user/tkt_user" | python3 -m json.tool

echo
echo "### 6. Verify spaces visible to each user"
echo "--- grc_user spaces ---"
curl -s -u "grc_user:<TENANT1_PASSWORD>" -H "$X" "$KB/api/spaces/space"; echo
echo "--- tkt_user spaces ---"
curl -s -u "tkt_user:<TENANT2_PASSWORD>" -H "$X" "$KB/api/spaces/space"; echo

echo
echo "### 7. Detection engine (should now be 200)"
curl -s -u "$U" -H "$X" "$KB/api/detection_engine/rules/_find?per_page=1" | head -c 500
echo
echo "DONE"
