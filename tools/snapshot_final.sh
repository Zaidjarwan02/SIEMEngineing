#!/usr/bin/env bash
# Final, clean-state snapshot for documentation. Read-only.
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'
C="curl -s --max-time 10 -u $ADMIN"
K="curl -s --max-time 10 -u $ADMIN -H $X"
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "CLUSTER"
$C "$ES/" | python3 -m json.tool 2>/dev/null
$C "$ES/_cluster/health?pretty"
$C "$ES/_cat/nodes?v&h=name,ip,version,roles,heap.percent,ram.percent,cpu,disk.avail"

sec "LICENSE"
$C "$ES/_license?pretty" | python3 -c "import sys,json;d=json.load(sys.stdin);print(json.dumps({'type':d.get('license',{}).get('type'),'status':d.get('license',{}).get('status'),'expiry':d.get('license',{}).get('expiry_date_in_millis')},indent=2))" 2>/dev/null

sec "NON-SYSTEM USERS"
$C "$ES/_security/user" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for u,v in sorted(d.items()):
    if v.get('metadata',{}).get('_reserved'): continue
    print(f\"{u:12s} roles={v.get('roles')} enabled={v.get('enabled')} metadata={v.get('metadata')}\")
" 2>/dev/null

sec "CUSTOM ROLES"
$C "$ES/_security/role" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in ('greencircle','tkt'):
    if r in d:
        v=d[r]
        print(f'--- {r} ---')
        print(json.dumps({'cluster':v.get('cluster'),'indices':v.get('indices'),'applications':v.get('applications'),'description':v.get('description')},indent=2))
" 2>/dev/null

sec "SPACES"
$K "$KB/api/spaces/space" | python3 -m json.tool 2>/dev/null

sec "DATA VIEWS PER SPACE"
for sp in greencircle tkt; do
  echo "--- space $sp ---"
  curl -s --max-time 10 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/data_views" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);[print('  ',v.get('name'),'->',v.get('title')) for v in d.get('data_view',[])]" 2>/dev/null
done

sec "DETECTION RULES PER SPACE"
for sp in default greencircle tkt; do
  total=$(curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('total','?'))" 2>/dev/null)
  enabled=$(curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('total','?'))" 2>/dev/null)
  pkg=$(curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/s/$sp/internal/detection_engine/prebuilt_rules/status" \
    | python3 -c "import sys,json;d=json.load(sys.stdin).get('stats',{});print(d.get('num_prebuilt_rules_installed','?'),'installed /',d.get('num_prebuilt_rules_total_in_package','?'),'in package')" 2>/dev/null)
  echo "space $sp: total=$total enabled=$enabled prebuilt=$pkg"
done
echo -n "installed security_detection_engine version: "
curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/api/fleet/epm/packages/security_detection_engine" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);i=d.get('item',d);print(i.get('version'),i.get('status'))" 2>/dev/null

sec "DASHBOARDS PER SPACE (should be empty after test cleanup)"
for sp in default greencircle tkt; do
  n=$(curl -s --max-time 10 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/saved_objects/_find?type=dashboard&per_page=1" | python3 -c "import sys,json;print(json.load(sys.stdin).get('total','?'))" 2>/dev/null)
  echo "space $sp dashboards: $n"
done

sec "DATA STREAMS (tenant test streams should be gone)"
$C "$ES/_data_stream?pretty" | python3 -c "
import sys,json
d=json.load(sys.stdin)
names=[x['name'] for x in d.get('data_streams',[])]
print('total:',len(names))
for n in names:
    if any(k in n for k in ('test','greencircle','tkt')): print('  tenant-like:',n)
" 2>/dev/null

sec "INDICES (non-system)"
$C "$ES/_cat/indices?h=health,status,index,docs.count,store.size&s=index" | grep -vE '^\.|^health' | head -n 40

sec "FLEET AGENT POLICIES"
$K "$KB/api/fleet/agent_policies?perPage=100" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for p in d.get('items',[]):
    print(f\"{p['name']:20s} namespace={p.get('namespace'):12s} agents={p.get('agents')} status={p.get('status')}\")
" 2>/dev/null

sec "FLEET AGENTS"
$K "$KB/api/fleet/agents?perPage=100" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('total:',d.get('total'))
for a in d.get('items',[]):
    print(f\"{a.get('id')} host={a.get('local_metadata',{}).get('host',{}).get('hostname')} status={a.get('status')} policy={a.get('policy_id')}\")
" 2>/dev/null

sec "KIBANA ENCRYPTION KEYS (masked)"
grep -E '^xpack\.(encryptedSavedObjects|reporting|security)\.encryptionKey:' /etc/kibana/kibana.yml | sed -E 's/(Key: ").*(")/\1********\2/'

sec "SECURITY POSTURE"
echo "--- ufw ---"; ufw status verbose 2>/dev/null
echo "--- listen ---"; ss -tulpn 2>/dev/null | grep -E ':(22|80|443|5601|9200|9300|8220|8221)\b'
echo "--- ES http ssl ---"; grep -E '^xpack\.security\.http\.ssl|^xpack\.security\.transport\.ssl|^xpack\.security\.enabled|^http\.host|^network\.host|^discovery' /etc/elasticsearch/elasticsearch.yml
echo "--- Kibana host/ssl ---"; grep -E '^server\.(host|port|ssl)|^elasticsearch\.(hosts|ssl)' /etc/kibana/kibana.yml
echo "--- plaintext kibana_system password present ---"; grep -q '^elasticsearch.password:' /etc/kibana/kibana.yml && echo YES || echo NO
echo "--- swap ---"; free -h | grep -i swap

sec "END"
