#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'
J='Content-Type: application/json'
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "CLUSTER HEALTH"
curl -s --max-time 15 -u "$ADMIN" "$ES/_cluster/health?pretty" | head -20

sec "NODE RESOURCES"
curl -s --max-time 15 -u "$ADMIN" "$ES/_cat/nodes?v&h=name,heap.percent,ram.percent,cpu,load_1m,node.role" | head -10
free -h
nproc

sec "LICENSE"
curl -s --max-time 15 -u "$ADMIN" "$ES/_license?pretty" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('license',{}).get('type'),d.get('license',{}).get('status'))" 2>/dev/null

sec "ALERT INDICES"
curl -s --max-time 30 -u "$ADMIN" "$ES/_cat/indices/.alerts-security.alerts-*,.internal.alerts-security.alerts-*?h=index,docs.count,store.size&s=index" | head -30

sec "RULE COUNTS PER SPACE"
for sp in default grcico-com tkt-org; do
  echo -n "  $sp total="
  curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('total','ERR'))" 2>/dev/null
  echo -n "  $sp enabled="
  curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('total','ERR'))" 2>/dev/null
done

sec "BULK ACTION ENDPOINT PROBE (empty ids)"
for sp in default grcico-com tkt-org; do
  echo -n "  $sp POST _bulk_action: "
  curl -s -o /tmp/bulk_probe_$sp.json -w '%{http_code}\n' --max-time 30 -u "$ADMIN" -H "$X" -H "$J" \
    -X POST "$KB/s/$sp/api/detection_engine/rules/_bulk_action" -d '{"action":"enable","ids":[]}'
  head -c 250 /tmp/bulk_probe_$sp.json; echo
done

sec "TENANT ROLE CLUSTER PRIVILEGES"
for r in GreenCircle tkt; do
  echo -n "  $r cluster: "
  curl -s --max-time 15 -u "$ADMIN" "$ES/_security/role/$r" \
    | python3 -c "import sys,json;w=json.load(sys.stdin);d=w[list(w.keys())[0]];print(d.get('cluster'))" 2>/dev/null
done

sec "API KEY COUNT"
curl -s --max-time 15 -u "$ADMIN" -H "$J" -X POST "$ES/_security/_query/api_key?pretty" -d '{"query":{"match_all":{}},"size":0}' | head -8

sec "DETECTION ENGINE HEALTH"
curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/api/detection_engine/health/_cluster" | head -c 600; echo
echo DONE
