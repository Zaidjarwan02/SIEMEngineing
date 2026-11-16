#!/usr/bin/env bash
# Restore canonical tenant roles AND grant read-only access to the shared
# Default space. Static JSON on purpose: the previous version parsed the
# wrapped GET response {"<role>": {...}} and wrote an empty role.
#
# Result per role:
#   - full read/write on own data namespace (+ own alert indices)
#   - space_all on own space
#   - space_read on space:default (shared general space, read-only)
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "1. PUT canonical role greencircle (+ space_read on default)"
cat > /tmp/role_greencircle_restore.json <<'EOF'
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
      "resources": ["space:greencircle"]
    },
    {
      "application": "kibana-.kibana",
      "privileges": ["space_read"],
      "resources": ["space:default"]
    }
  ],
  "description": "Tenant 1 (greencircle): full read/write on its greencircle data streams and greencircle-* indices; full UI in space greencircle; read-only in the shared Default space and its alerts."
}
EOF
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X PUT "$ES/_security/role/greencircle" \
  -d @/tmp/role_greencircle_restore.json | head -c 400; echo

sec "2. PUT canonical role tkt (+ space_read on default)"
cat > /tmp/role_tkt_restore.json <<'EOF'
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
      "resources": ["space:tkt"]
    },
    {
      "application": "kibana-.kibana",
      "privileges": ["space_read"],
      "resources": ["space:default"]
    }
  ],
  "description": "Tenant 2 (TKT): full read/write on its tkt data streams and tkt-* indices; full UI in space tkt; read-only in the shared Default space and its alerts."
}
EOF
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X PUT "$ES/_security/role/tkt" \
  -d @/tmp/role_tkt_restore.json | head -c 400; echo

sec "3. VERIFY role definitions (unwrapped)"
for r in greencircle tkt; do
  echo "--- $r ---"
  curl -s --max-time 30 -u "$ADMIN" "$ES/_security/role/$r" | python3 -c "
import sys,json
w=json.load(sys.stdin)
d=w[list(w.keys())[0]]
print('  cluster:',d.get('cluster'))
for i in d.get('indices',[]):
    print('  index:',i.get('names'),i.get('privileges'),'restricted=',i.get('allow_restricted_indices'))
for a in d.get('applications',[]):
    print('  app:',a.get('application'),a.get('privileges'),a.get('resources'))
" 2>&1
done

sec "4. SPACE VISIBILITY PER TENANT"
for pair in "T1_user:<TENANT1_PASSWORD>" "T2_user:<TENANT2_PASSWORD>"; do
  u=$(echo "$pair" | cut -d: -f1); c=$(echo "$pair" | cut -d: -f2)
  echo -n "$u spaces: "
  curl -s --max-time 30 -u "$c" -H "$X" "$KB/api/spaces/space" \
    | python3 -c "import sys,json;print(sorted(s['id'] for s in json.load(sys.stdin)))" 2>&1
done

sec "5. DEFAULT SPACE READ (should be 200, shared)"
for pair in "T1_user:<TENANT1_PASSWORD>" "T2_user:<TENANT2_PASSWORD>"; do
  u=$(echo "$pair" | cut -d: -f1); c=$(echo "$pair" | cut -d: -f2)
  echo -n "$u GET default saved objects: "
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 30 -u "$c" -H "$X" \
    "$KB/s/default/api/saved_objects/_find?type=dashboard&per_page=1"
done

sec "6. DEFAULT SPACE WRITE (should be 403, read-only)"
for pair in "T1_user:<TENANT1_PASSWORD>" "T2_user:<TENANT2_PASSWORD>"; do
  u=$(echo "$pair" | cut -d: -f1); c=$(echo "$pair" | cut -d: -f2)
  echo -n "$u POST dashboard into default: "
  curl -s -o /tmp/dw_$u.json -w '%{http_code}\n' --max-time 30 -u "$c" -H "$X" -H "$J" \
    -X POST "$KB/s/default/api/saved_objects/dashboard" \
    -d '{"attributes":{"title":"probe-shared-default-write","hits":0,"description":"probe","panelsJSON":"[]","optionsJSON":"{}","version":1,"timeRestore":false}}'
  head -c 200 /tmp/dw_$u.json; echo
done

sec "7. OWN SPACE WRITE (should be 200, full access)"
for pair in "T1_user:<TENANT1_PASSWORD>:greencircle" "T2_user:<TENANT2_PASSWORD>:tkt"; do
  u=$(echo "$pair" | cut -d: -f1); c=$(echo "$pair" | cut -d: -f2); sp=$(echo "$pair" | cut -d: -f3)
  echo -n "$u POST dashboard into $sp: "
  curl -s -o /tmp/ow_$u.json -w '%{http_code}\n' --max-time 30 -u "$c" -H "$X" -H "$J" \
    -X POST "$KB/s/$sp/api/saved_objects/dashboard" \
    -d '{"attributes":{"title":"probe-own-space-write","hits":0,"description":"probe","panelsJSON":"[]","optionsJSON":"{}","version":1,"timeRestore":false}}'
  ID=$(python3 -c "import json;print(json.load(open('/tmp/ow_$u.json')).get('id',''))" 2>/dev/null)
  echo "   created id=$ID"
  [ -n "$ID" ] && curl -s -o /dev/null -w "   cleanup delete -> %{http_code}\n" --max-time 30 \
    -u "$c" -H "$X" -X DELETE "$KB/s/$sp/api/saved_objects/dashboard/$ID"
done

sec "8. CROSS-TENANT STILL BLOCKED (should be 403)"
echo -n "T1_user -> tkt saved objects: "
curl -s -o /dev/null -w '%{http_code}\n' --max-time 30 -u "T1_user:<TENANT1_PASSWORD>" -H "$X" \
  "$KB/s/tkt/api/saved_objects/_find?type=dashboard&per_page=1"
echo -n "T2_user -> greencircle saved objects: "
curl -s -o /dev/null -w '%{http_code}\n' --max-time 30 -u "T2_user:<TENANT2_PASSWORD>" -H "$X" \
  "$KB/s/greencircle/api/saved_objects/_find?type=dashboard&per_page=1"

sec "END"
