#!/usr/bin/env bash
set +e
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'

echo "=== stable sort created_at asc, page 1 vs 2 ==="
for p in 1 2; do
  echo -n "page $p: "
  curl -s --max-time 60 -u "$ADMIN" -H "$X" \
    "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=3&page=$p&sort_field=created_at&sort_order=asc" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print([r.get('rule_id') for r in d.get('data',[])])" 2>/dev/null
done

echo "=== 200-rule page size/time ==="
curl -s --max-time 180 -u "$ADMIN" -H "$X" \
  "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=200&page=1&sort_field=created_at&sort_order=asc" \
  -o /tmp/page200.json -w 'http=%{http_code} bytes=%{size_download} time=%{time_total}s\n'
python3 -c "import json;d=json.load(open('/tmp/page200.json'));print('rules:',len(d.get('data',[])))" 2>/dev/null

echo "=== saved-object namespace fields ==="
curl -s --max-time 30 -u "$ADMIN" -H 'Content-Type: application/json' -X POST \
  "http://127.0.0.1:9200/.kibana_security_solution_8.19.24_001/_search?size=3" \
  -d '{"query":{"term":{"type":"security-rule"}},"_source":["type","namespace","namespaces","security-rule.rule_id"]}' \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for h in d['hits']['hits']:
    print(' id=',h['_id'],'src=',json.dumps(h['_source'])[:250])
" 2>/dev/null
echo DONE
