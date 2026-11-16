#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="greencircle_user:<TENANT1_PASSWORD>"
X='kbn-xsrf: true'
J='Content-Type: application/json'

curl -s --max-time 90 -u "$ADMIN" -H "$X" "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=3" -o /tmp/bulk3.json
python3 - <<'PY'
import json
d=json.load(open('/tmp/bulk3.json'))
for r in d['data']:
    print('id=',r['id'],'rule_id=',r['rule_id'],'enabled=',r.get('enabled'))
PY

IDS=$(python3 - <<'PY'
import json
d=json.load(open('/tmp/bulk3.json'))
print(json.dumps([r['id'] for r in d['data']]))
PY
)
echo "ids payload: $IDS"

echo "=== bulk enable (3) as greencircle_user ==="
curl -s -o /tmp/bulk_enable3.json -w 'http=%{http_code}\n' --max-time 120 -u "$TENANT1" -H "$X" -H "$J" \
  -X POST "$KB/s/greencircle/api/detection_engine/rules/_bulk_action" \
  -d "{\"action\":\"enable\",\"ids\":$IDS}"
head -c 500 /tmp/bulk_enable3.json; echo

echo "=== enabled count ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null

echo "=== bulk disable (3) as greencircle_user ==="
curl -s -o /tmp/bulk_disable3.json -w 'http=%{http_code}\n' --max-time 120 -u "$TENANT1" -H "$X" -H "$J" \
  -X POST "$KB/s/greencircle/api/detection_engine/rules/_bulk_action" \
  -d "{\"action\":\"disable\",\"ids\":$IDS}"
head -c 500 /tmp/bulk_disable3.json; echo

echo "=== enabled count ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null
echo DONE
