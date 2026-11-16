#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
U="elastic:<ADMIN_PASSWORD>"
C="curl -s --max-time 10 -u $U"
K="curl -s --max-time 10 -u $U -H kbn-xsrf:true"
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "FLEET AGENT POLICIES"
$K "$KB/api/fleet/agent_policies?perPage=100" | head -c 4000
echo
sec "FLEET ENROLLMENT KEYS"
$K "$KB/api/fleet/enrollment_api_keys" | head -c 3000
echo
sec "FLEET OUTPUTS"
$K "$KB/api/fleet/outputs" | head -c 3000
echo
sec "FLEET SERVER HOSTS"
$K "$KB/api/fleet/fleet_server_hosts" | head -c 2000
echo
sec "FLEET SETTINGS"
$K "$KB/api/fleet/settings" | head -c 2000
echo
sec "DETECTION RULES"
$K "$KB/api/detection_engine/rules/_find?per_page=100" | head -c 3000
echo
sec "DETECTION ENGINE STATUS"
$K "$KB/api/detection_engine/status" | head -c 1000
echo
sec "ALERT INDICES"
$C "$ES/_cat/indices/.alerts*,.internal.alerts*?v&h=index,docs.count,store.size" 2>/dev/null
sec "ES HEAP OPTIONS"
grep -HnE '^-Xm|^[^#].*Xm' /etc/elasticsearch/jvm.options /etc/elasticsearch/jvm.options.d/* 2>/dev/null
echo "--- elasticsearch process ---"
ps -o pid,rss,cmd -C java | head -n 5
echo "--- kibana process ---"
ps -eo pid,rss,cmd | grep -i '[k]ibana' | head -n 3
echo "--- top mem ---"
ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 8
sec "KIBANA KEYSTORE"
/usr/share/kibana/bin/kibana-keystore list 2>/dev/null
sec "ENCRYPTION KEYS IN CONFIG"
grep -Ei 'encryptionKey|savedObjects|security\.encryption' /etc/kibana/kibana.yml 2>/dev/null || echo "none configured"
sec "SPACES (raw)"
$K "$KB/api/spaces/space"
echo
sec "INDEX PATTERNS PER SPACE"
for sp in default greencircle tkt; do
  echo "--- space $sp ---"
  curl -s --max-time 10 -u "$U" -H kbn-xsrf:true "$KB/s/$sp/api/saved_objects/_find?type=index-pattern&per_page=100" | head -c 2000
  echo
done
sec "END"
