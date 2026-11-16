#!/usr/bin/env bash
# Provision multi-tenant access for the Elastic MSSP test cluster.
#   Tenant 1: greencircle  -> space greencircle, data namespace greencircle
#   Tenant 2: TKT          -> space tkt,    data namespace tkt
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
      "names": ["greencircle-*"],
      "privileges": ["all"],
      "allow_restricted_indices": false
    },
    {
      "names": [
        ".alerts-security.alerts-greencircle*",
        ".internal.alerts-security.alerts-greencircle*"
      ],
      "privileges": ["all"],
      "allow_restricted_indices": true
    }
  ],
  "applications": [
    {
      "application": "kibana-.kibana",
      "privileges": ["space_all"],
      "resources": ["space:greencircle"]
    }
  ],
  "description": "Tenant 1 (greencircle): full read/write on its greencircle data streams and greencircle-* indices; UI access limited to space greencircle."
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
        ".alerts-security.alerts-tkt*",
        ".internal.alerts-security.alerts-tkt*"
      ],
      "privileges": ["all"],
      "allow_restricted_indices": true
    }
  ],
  "applications": [
    {
      "application": "kibana-.kibana",
      "privileges": ["space_all"],
      "resources": ["space:tkt"]
    }
  ],
  "description": "Tenant 2 (TKT): full read/write on its tkt data streams and tkt-* indices; UI access limited to space tkt."
}
EOF

echo -n "greencircle: "; curl -s -u "$U" -H "$J" -X PUT "$ES/_security/role/greencircle" -d @/tmp/role_greencircle.json; echo
echo -n "tkt:         "; curl -s -u "$U" -H "$J" -X PUT "$ES/_security/role/tkt" -d @/tmp/role_tkt.json; echo

echo
echo "### 2. Users"

cat > /tmp/user_greencircle.json <<'EOF'
{
  "password": "<TENANT1_PASSWORD>",
  "roles": ["greencircle"],
  "full_name": "greencircle Tenant User",
  "email": "greencircle_user@greencircle.local",
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

echo -n "greencircle_user: "; curl -s -u "$U" -H "$J" -X PUT "$ES/_security/user/greencircle_user" -d @/tmp/user_greencircle.json; echo
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

mkview greencircle 'logs-*-greencircle*'   'greencircle Logs'
mkview greencircle 'metrics-*-greencircle*' 'greencircle Metrics'
mkview greencircle 'greencircle-*'                  'greencircle Custom (greencircle-*)'
mkview tkt    'logs-*-tkt*'            'TKT Logs'
mkview tkt    'metrics-*-tkt*'         'TKT Metrics'
mkview tkt    'tkt-*'                  'TKT Custom (tkt-*)'

echo
echo "### 4. Verify role definitions"
curl -s -u "$U" "$ES/_security/role/greencircle" | python3 -m json.tool
curl -s -u "$U" "$ES/_security/role/tkt" | python3 -m json.tool

echo
echo "### 5. Verify users"
curl -s -u "$U" "$ES/_security/user/greencircle_user" | python3 -m json.tool
curl -s -u "$U" "$ES/_security/user/tkt_user" | python3 -m json.tool

echo
echo "### 6. Verify spaces visible to each user"
echo "--- greencircle_user spaces ---"
curl -s -u "greencircle_user:<TENANT1_PASSWORD>" -H "$X" "$KB/api/spaces/space"; echo
echo "--- tkt_user spaces ---"
curl -s -u "tkt_user:<TENANT2_PASSWORD>" -H "$X" "$KB/api/spaces/space"; echo

echo
echo "### 7. Detection engine (should now be 200)"
curl -s -u "$U" -H "$X" "$KB/api/detection_engine/rules/_find?per_page=1" | head -c 500
echo
echo "DONE"
