#!/usr/bin/env bash
# Make the Default space a shared "general" space for all tenants (read-only).
# Keeps each tenant's full read/write in its own space and preserves data isolation.
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
ADMIN="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'
sec() { printf '\n\n========== %s ==========\n' "$1"; }

update_role() {
  role="$1"; ownspace="$2"
  echo "--- updating role $role (own space: $ownspace, shared: default read-only) ---"
  curl -s --max-time 30 -u "$ADMIN" "$ES/_security/role/$role" -o "/tmp/role_$role.json"
  python3 - "$role" "$ownspace" <<'PY' > "/tmp/role_${role}_new.json"
import json,sys
role,own=sys.argv[1],sys.argv[2]
d=json.load(open(f'/tmp/role_{role}.json'))
apps=[a for a in d.get('applications',[]) if 'space:default' not in a.get('resources',[])]
apps.append({"application":"kibana-.kibana","privileges":["space_read"],"resources":["space:default"]})
out={
  "cluster": d.get("cluster",[]),
  "indices": d.get("indices",[]),
  "applications": apps,
  "description": d.get("description","")
}
if d.get("run_as"): out["run_as"]=d["run_as"]
if d.get("metadata"): out["metadata"]=d["metadata"]
print(json.dumps(out,indent=2))
PY
  curl -s --max-time 30 -u "$ADMIN" -H "$J" -X PUT "$ES/_security/role/$role" \
    -d @"/tmp/role_${role}_new.json" | head -c 400; echo
}

sec "UPDATE ROLES"
update_role GreenCircle grcico-com
update_role tkt tkt-org

sec "EFFECTIVE ROLE APPLICATIONS"
for r in GreenCircle tkt; do
  echo "--- $r ---"
  curl -s -u "$ADMIN" "$ES/_security/role/$r" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for a in d.get('applications',[]):
    print(' ',a.get('application'),a.get('privileges'),a.get('resources'))
print('  cluster:',d.get('cluster'))
print('  indices:',[i.get('names') for i in d.get('indices',[])])
" 2>/dev/null
done

sec "TENANT SPACE VISIBILITY"
GRC="grc_user:<TENANT1_PASSWORD>"; TKT="tkt_user:<TENANT2_PASSWORD>"
for pair in "grc_user:$GRC" "tkt_user:$TKT"; do
  u=$(echo "$pair" | cut -d: -f1); c=$(echo "$pair" | cut -d: -f2)
  echo -n "$u spaces: "
  curl -s --max-time 30 -u "$c" -H 'kbn-xsrf: true' "http://127.0.0.1:5601/api/spaces/space" \
    | python3 -c "import sys,json;print([s['id'] for s in json.load(sys.stdin)])" 2>/dev/null
done

sec "END"
