#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="greencircle_user:<TENANT1_PASSWORD>"
X='kbn-xsrf: true'
J='Content-Type: application/json'

echo "=== probe query-based bulk action (non-matching query) ==="
curl -s -o /tmp/qprobe.json -w 'http=%{http_code}\n' --max-time 60 -u "$ADMIN" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/detection_engine/rules/_bulk_action" \
  -d '{"action":"enable","query":"alert.attributes.name:\"zzz-no-such-rule\""}'
head -c 300 /tmp/qprobe.json; echo

echo "=== fetch 50 ids from greencircle ==="
curl -s --max-time 180 -u "$ADMIN" -H "$X" "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=50" -o /tmp/bulk50.json
IDS=$(python3 - <<'PY'
import json
d=json.load(open('/tmp/bulk50.json'))
print(json.dumps([r['id'] for r in d['data']]))
PY
)
N=$(python3 -c "import json;print(len(json.load(open('/tmp/bulk50.json'))['data']))")
echo "rules fetched: $N"

echo "=== bulk enable 50 as greencircle_user (timed) ==="
START=$(date +%s)
curl -s -o /tmp/bulk50_en.json -w 'http=%{http_code} time=%{time_total}s\n' --max-time 500 -u "$TENANT1" -H "$X" -H "$J" \
  -X POST "$KB/s/greencircle/api/detection_engine/rules/_bulk_action" \
  -d "{\"action\":\"enable\",\"ids\":$IDS}"
echo "elapsed=$(( $(date +%s)-START ))s"
python3 -c "import json;d=json.load(open('/tmp/bulk50_en.json'));print('success',d.get('success'),'count',d.get('rules_count'),'errors',len(d.get('errors',[])))" 2>/dev/null

echo "=== enabled count ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null

echo "=== bulk disable 50 as greencircle_user ==="
START=$(date +%s)
curl -s -o /tmp/bulk50_dis.json -w 'http=%{http_code} time=%{time_total}s\n' --max-time 500 -u "$TENANT1" -H "$X" -H "$J" \
  -X POST "$KB/s/greencircle/api/detection_engine/rules/_bulk_action" \
  -d "{\"action\":\"disable\",\"ids\":$IDS}"
echo "elapsed=$(( $(date +%s)-START ))s"
python3 -c "import json;d=json.load(open('/tmp/bulk50_dis.json'));print('success',d.get('success'),'count',d.get('rules_count'),'errors',len(d.get('errors',[])))" 2>/dev/null
echo DONE
