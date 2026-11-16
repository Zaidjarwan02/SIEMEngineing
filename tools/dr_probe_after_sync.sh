#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
GRC="grc_user:<TENANT1_PASSWORD>"; TKT="tkt_user:<TENANT2_PASSWORD>"
X='kbn-xsrf: true'

echo "=== counts per space (admin) ==="
for sp in default grcico-com tkt-org; do
  echo -n "  $sp: "
  curl -s --max-time 90 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null
done

echo "=== tenant view of default rules ==="
for pair in "grc_user:<TENANT1_PASSWORD>" "tkt_user:<TENANT2_PASSWORD>"; do
  u=${pair%%:*}
  echo -n "  $u default rules: "
  curl -s --max-time 90 -u "$pair" -H "$X" -w ' (http %{http_code})' "$KB/s/default/api/detection_engine/rules/_find?per_page=1" \
    | python3 -c "
import sys
raw=sys.stdin.read()
import json
try:
    body,code=raw.rsplit(' (http ',1)
    d=json.loads(body)
    print('total',d.get('total'),'http',code.strip(')'))
except Exception:
    print(raw[:200])
" 2>/dev/null
done

echo "=== known tkt rule id ==="
TKTID=$(curl -s --max-time 90 -u "$ADMIN" -H "$X" "$KB/s/tkt-org/api/detection_engine/rules/_find?per_page=1" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null)
echo "  $TKTID"

echo "=== grc direct access to tkt rule ==="
echo -n "  via tkt-org GET: "
curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 -u "$GRC" -H "$X" "$KB/s/tkt-org/api/detection_engine/rules?id=$TKTID"
echo -n "  via default GET: "
curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 -u "$GRC" -H "$X" "$KB/s/default/api/detection_engine/rules?id=$TKTID"
echo -n "  via default DELETE: "
curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 -u "$GRC" -H "$X" -X DELETE "$KB/s/default/api/detection_engine/rules?id=$TKTID"
echo -n "  via tkt-org DELETE: "
curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 -u "$GRC" -H "$X" -X DELETE "$KB/s/tkt-org/api/detection_engine/rules?id=$TKTID"

echo "=== duplicates check ==="
for sp in default grcico-com tkt-org; do
  curl -s --max-time 300 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=10000" -o "/tmp/r_$sp.json"
  python3 - "$sp" <<'PY'
import json,sys,collections
sp=sys.argv[1]
d=json.load(open(f'/tmp/r_{sp}.json'))
by=collections.Counter(r.get('attributes',r).get('rule_id') for r in d.get('data',[]))
dups=[k for k,v in by.items() if v>1]
print(f'  {sp}: unique={len(by)} dups={len(dups)}')
PY
done

echo "=== api key count ==="
curl -s --max-time 30 -u "$ADMIN" -H 'Content-Type: application/json' -X POST \
  "http://127.0.0.1:9200/_security/_query/api_key?pretty" -d '{"query":{"match_all":{}},"size":0}' | head -c 150; echo
echo DONE
