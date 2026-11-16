#!/usr/bin/env bash
# Inspect the running Elastic stack using the elastic superuser.
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
U="elastic:<ADMIN_PASSWORD>"
C="curl -s --max-time 10 -u $U"
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "ELASTICSEARCH ROOT"
$C "$ES/"

sec "CLUSTER HEALTH"
$C "$ES/_cluster/health?pretty"

sec "NODES"
$C "$ES/_cat/nodes?v&h=name,ip,version,roles,heap.percent,ram.percent,cpu,load_1m,disk.avail"

sec "LICENSE"
$C "$ES/_license?pretty"

sec "AUTHENTICATED USER"
$C "$ES/_security/_authenticate?pretty"

sec "INDICES"
$C "$ES/_cat/indices?v&s=index&h=health,status,index,uuid,pri,rep,docs.count,store.size"

sec "DATA STREAMS"
$C "$ES/_data_stream?pretty"

sec "TEMPLATES"
$C "$ES/_index_template?pretty" | head -c 3000
echo
$C "$ES/_component_template?pretty" | head -c 3000

sec "SECURITY USERS"
$C "$ES/_security/user?pretty"

sec "SECURITY ROLES (names)"
$C "$ES/_security/role?pretty" | python3 -c "import sys,json; d=json.load(sys.stdin); print('\n'.join(sorted(d.keys())))" 2>/dev/null || $C "$ES/_security/role"

sec "SECURITY ROLE MAPPINGS"
$C "$ES/_security/role_mapping?pretty"

sec "API KEYS"
$C "$ES/_security/api_key?pretty"

sec "SNAPSHOT REPOS"
$C "$ES/_snapshot?pretty"

sec "KIBANA SPACES"
curl -s --max-time 10 -u "$U" -H 'kbn-xsrf: true' "$KB/api/spaces/space?pretty"

sec "KIBANA STATUS"
curl -s --max-time 10 -u "$U" "$KB/api/status"

sec "KIBANA SAVED OBJECTS COUNT"
curl -s --max-time 10 -u "$U" -H 'kbn-xsrf: true' "$KB/api/saved_objects/_find?type=index-pattern&per_page=100" | head -c 3000

sec "ELASTICSEARCH.YML (effective, no secrets)"
grep -vE '^\s*#|^\s*$' /etc/elasticsearch/elasticsearch.yml

sec "KIBANA.YML (effective, no secrets)"
grep -vE '^\s*#|^\s*$' /etc/kibana/kibana.yml

sec "JVM HEAP SETTINGS"
grep -rE '^-Xm' /etc/elasticsearch/jvm.options /etc/elasticsearch/jvm.options.d/ 2>/dev/null
cat /etc/kibana/node.options 2>/dev/null

sec "CERTS"
ls -la /etc/elasticsearch/certs 2>/dev/null

sec "END"
