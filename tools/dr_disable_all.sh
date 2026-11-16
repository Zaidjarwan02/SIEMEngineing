#!/usr/bin/env bash
# Disable every enabled detection rule in each space (clean baseline).
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'

for sp in default grcico-com tkt-org; do
  echo "=== space $sp ==="
  ids=$(curl -s --max-time 90 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=100&filter=alert.attributes.enabled:true" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',[]):
    a=r.get('attributes',r)
    print(a.get('rule_id'))
" 2>/dev/null)
  if [ -z "$ids" ]; then echo "  none enabled"; continue; fi
  for rid in $ids; do
    echo -n "  disable $rid: "
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 -u "$ADMIN" -H "$X" -H 'Content-Type: application/json' \
      -X PATCH "$KB/s/$sp/api/detection_engine/rules" -d "{\"rule_id\":\"$rid\",\"enabled\":false}"
  done
done

echo
echo "=== enabled counts after ==="
for sp in default grcico-com tkt-org; do
  echo -n "space $sp enabled: "
  curl -s --max-time 60 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null
done

echo
echo "=== API key count ==="
curl -s --max-time 30 -u "$ADMIN" -H 'Content-Type: application/json' -X POST \
  "http://127.0.0.1:9200/_security/_query/api_key?pretty" \
  -d '{"query":{"match_all":{}},"size":0}' 2>/dev/null | head -c 200; echo
echo DONE
