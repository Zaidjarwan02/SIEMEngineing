#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'
J='Content-Type: application/json'

RID=$(curl -s --max-time 60 -u "$ADMIN" -H "$X" \
  "$KB/s/default/api/detection_engine/rules/_find?per_page=10000&page=1" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print([r['id'] for r in d['data'] if r.get('rule_id')=='a198fbbd-9413-45ec-a269-47ae4ccf59ce'][0])" 2>/dev/null)
echo "My First Rule internal id: $RID"

echo "=== probe bulk action run ==="
curl -s -o /tmp/run1.json -w 'http=%{http_code}\n' --max-time 120 -u "$ADMIN" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/detection_engine/rules/_bulk_action" \
  -d "{\"action\":\"run\",\"ids\":[\"$RID\"]}"
head -c 400 /tmp/run1.json; echo

echo "=== probe rule execute endpoint ==="
curl -s -o /tmp/run2.json -w 'http=%{http_code}\n' --max-time 120 -u "$ADMIN" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/detection_engine/rules/_execute" \
  -d "{\"id\":\"$RID\"}"
head -c 400 /tmp/run2.json; echo

echo "=== alert count default now ==="
curl -s --max-time 30 -u "$ADMIN" "$KB/../" >/dev/null 2>&1
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "http://127.0.0.1:9200/.internal.alerts-security.alerts-default*/_count" \
  -d '{"query":{"match_all":{}}}'
echo
echo DONE
