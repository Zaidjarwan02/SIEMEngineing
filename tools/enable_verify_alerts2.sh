#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="T1_user:<TENANT1_PASSWORD>"
TKT="T2_user:<TENANT2_PASSWORD>"
X='kbn-xsrf: true'
J='Content-Type: application/json'

echo "=== alert doc ids in default ==="
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.internal.alerts-security.alerts-default*/_search?size=5" \
  -d '{"query":{"match_all":{}},"_source":["kibana.alert.rule.name"]}' \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for h in d.get('hits',{}).get('hits',[]):
    print(h['_id'],'|',h['_source'].get('kibana.alert.rule.name'))
" 2>&1

echo
echo "=== signals/search variants as T1_user in default ==="
echo -n "  variant A (es query dsl): "
curl -s -o /tmp/a.json -w '%{http_code}\n' --max-time 60 -u "$TENANT1" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/detection_engine/signals/search" -d '{"query":{"bool":{"must":[]}},"size":10}'
head -c 160 /tmp/a.json; echo
echo -n "  variant B (kuery wrapper): "
curl -s -o /tmp/b.json -w '%{http_code}\n' --max-time 60 -u "$TENANT1" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/detection_engine/signals/search" -d '{"query":{"query":"","language":"kuery"},"size":10}'
head -c 160 /tmp/b.json; echo
echo -n "  variant C (alerts search endpoint): "
curl -s -o /tmp/c.json -w '%{http_code}\n' --max-time 60 -u "$TENANT1" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/detection_engine/alerts/search" -d '{"query":{"bool":{"must":[]}},"size":10}'
head -c 160 /tmp/c.json; echo

echo
echo "=== alert search via ES directly (tenant) ==="
echo -n "  greencircle search default alerts: "
curl -s --max-time 30 -u "$TENANT1" -H "$J" -X POST "$ES/.alerts-security.alerts-default*/_search?size=1" -d '{"query":{"match_all":{}}}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('hits',d.get('hits',{}).get('total',{}).get('value'))" 2>&1
echo -n "  greencircle search tkt alerts: "
curl -s --max-time 30 -u "$TENANT1" -H "$J" -X POST "$ES/.alerts-security.alerts-tkt*/_search?size=1" -d '{"query":{"match_all":{}}}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('hits',d.get('hits',{}).get('total',{}).get('value'))" 2>&1

echo
echo "=== ack a real alert as T1_user (expect blocked) ==="
AID=$(curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.internal.alerts-security.alerts-default*/_search?size=1" -d '{"query":{"match_all":{}}}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['hits']['hits'][0]['_id'])" 2>/dev/null)
echo "  alert id=$AID"
curl -s -o /tmp/ack2.json -w '  http=%{http_code}\n' --max-time 60 -u "$TENANT1" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/detection_engine/signals/status" -d "{\"signal_ids\":[\"$AID\"],\"status\":\"acknowledged\"}"
head -c 300 /tmp/ack2.json; echo

echo
echo "=== verify alert unchanged (status still open) ==="
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.internal.alerts-security.alerts-default*/_search?size=1" \
  -d '{"query":{"match_all":{}},"_source":["kibana.alert.workflow_status"]}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);h=d['hits']['hits'][0];print('  ',h['_id'],h['_source'].get('kibana.alert.workflow_status'))" 2>&1
echo DONE
