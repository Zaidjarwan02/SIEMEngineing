#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'; X='kbn-xsrf: true'

echo "=== count security-rule by namespaces term ==="
for ns in default grcico-com tkt-org; do
  echo -n "  namespaces=$ns: "
  curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.kibana_security_solution_8.19.24_001/_count" \
    -d "{\"query\":{\"term\":{\"namespaces\":\"$ns\"}}}" | head -c 150; echo
done

echo "=== sample _source keys of a security-rule doc ==="
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.kibana_security_solution_8.19.24_001/_search?size=1" \
  -d '{"query":{"term":{"type":"security-rule"}}}' \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
h=d.get('hits',{}).get('hits',[])
if not h: print(' no hits'); sys.exit()
s=h[0]['_source']
print(' _id:',h[0]['_id'])
print(' keys:',sorted(s.keys()))
for k in ('type','namespaces','space_ids','kibana','updated_at'):
    if k in s: print(' ',k,'=',json.dumps(s[k])[:300])
" 2>&1

echo "=== agg on namespaces.keyword / kibana.space_ids ==="
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.kibana_security_solution_8.19.24_001/_search?size=0" -d '{
 "query":{"term":{"type":"security-rule"}},
 "aggs":{"a":{"terms":{"field":"namespaces.keyword","size":10}},
         "b":{"terms":{"field":"kibana.space_ids","size":10}}}
}' | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' aggs:',json.dumps(d.get('aggregations',{}))[:600])
" 2>&1

echo "=== admin _find per space with explicit filter ==="
for sp in grcico-com tkt-org; do
  echo -n "  $sp (no filter): "
  curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print('total',d.get('total'),'err',d.get('message'))" 2>&1
done

echo "=== spaces list (admin) ==="
curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/api/spaces/space" | head -c 800; echo

echo "=== fleet packages installed ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/api/fleet/epm/packages?perPage=100" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for p in d.get('items',[]):
    print(' ',p.get('name'),p.get('version'),p.get('status'))
" 2>&1
echo DONE
