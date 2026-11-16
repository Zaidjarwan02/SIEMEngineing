#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'

echo "=== _find with fields + stable sort (5 rules) ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" \
  "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=5&page=1&sort_field=rule_id&sort_order=asc&fields=id,rule_id,enabled,name" \
  -o /tmp/find_fields.json -w 'http=%{http_code} bytes=%{size_download}\n'
python3 - <<'PY'
import json
d=json.load(open('/tmp/find_fields.json'))
print('keys:',sorted(d.keys()))
print('total:',d.get('total'))
for r in d.get('data',[]):
    print('  keys:',sorted(r.keys()))
    print('  ',r.get('id'),r.get('rule_id'),r.get('enabled'),str(r.get('name'))[:40])
    break
PY

echo "=== page 1 vs page 2 first id (sort stability) ==="
for p in 1 2; do
  echo -n "page $p: "
  curl -s --max-time 60 -u "$ADMIN" -H "$X" \
    "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=5&page=$p&sort_field=rule_id&sort_order=asc&fields=id,rule_id" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print([r.get('rule_id') for r in d.get('data',[])])" 2>/dev/null
done

echo "=== api key count ==="
curl -s --max-time 15 -u "$ADMIN" -H 'Content-Type: application/json' -X POST \
  "http://127.0.0.1:9200/_security/_query/api_key" -d '{"query":{"match_all":{}},"size":0}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null

echo "=== alert index aliases ==="
curl -s --max-time 15 -u "$ADMIN" "http://127.0.0.1:9200/_cat/aliases/.alerts-security.alerts-*?h=alias,index" | head -20
echo DONE
