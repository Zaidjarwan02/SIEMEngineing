#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
GRC="grc_user:<TENANT1_PASSWORD>"
X='kbn-xsrf: true'
J='Content-Type: application/json'

RID=$(curl -s --max-time 90 -u "$ADMIN" -H "$X" "$KB/s/grcico-com/api/detection_engine/rules/_find?per_page=1" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['data'][0]['rule_id'])" 2>/dev/null)
echo "chosen rule_id=$RID"

echo "=== enable as grc_user ==="
curl -s -o /tmp/grc_enable_one.json -w 'http=%{http_code}\n' --max-time 60 -u "$GRC" -H "$X" -H "$J" \
  -X PATCH "$KB/s/grcico-com/api/detection_engine/rules" -d "{\"rule_id\":\"$RID\",\"enabled\":true}"
head -c 600 /tmp/grc_enable_one.json; echo

echo "=== enabled count now ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/s/grcico-com/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null

echo "=== api key count now ==="
curl -s --max-time 15 -u "$ADMIN" -H "$J" -X POST "$ES/_security/_query/api_key" -d '{"query":{"match_all":{}},"size":0}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null

echo "=== disable it again ==="
curl -s -o /tmp/grc_disable_one.json -w 'http=%{http_code}\n' --max-time 60 -u "$GRC" -H "$X" -H "$J" \
  -X PATCH "$KB/s/grcico-com/api/detection_engine/rules" -d "{\"rule_id\":\"$RID\",\"enabled\":false}"
head -c 300 /tmp/grc_disable_one.json; echo
echo DONE
