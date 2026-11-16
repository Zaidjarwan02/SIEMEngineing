#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
ADMIN="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'

echo "=== security-rule docs per kibana index ==="
for idx in .kibana_8.19.24_001 .kibana_security_solution_8.19.24_001 .kibana_alerting_cases_8.19.24_001; do
  echo -n "  $idx: "
  curl -s --max-time 30 -u "$ADMIN" "$ES/$idx/_count?q=type:security-rule" | head -c 120; echo
done

echo "=== does mapping have namespaces? ==="
curl -s --max-time 30 -u "$ADMIN" "$ES/.kibana_security_solution_8.19.24_001/_mapping" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
m=list(d.values())[0]['mappings']['properties']
print(' top-level keys:',sorted(m.keys()))
print(' namespaces:',json.dumps(m.get('namespaces'))[:200])
" 2>&1

echo "=== distinct namespaces values (unmapped-safe) ==="
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.kibana_security_solution_8.19.24_001/_search?size=0" -d '{
 "query":{"term":{"type":"security-rule"}},
 "aggs":{"ns":{"terms":{"field":"namespaces","size":10,"missing":"<MISSING>"}}}
}' | python3 -c "
import sys,json
d=json.load(sys.stdin)
for b in d.get('aggregations',{}).get('ns',{}).get('buckets',[]): print('  ',b['key'],b['doc_count'])
" 2>&1

echo "=== sample doc with namespaces present? ==="
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.kibana_security_solution_8.19.24_001/_search?size=3" \
  -d '{"query":{"exists":{"field":"namespaces"}}}' \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' hits:',d.get('hits',{}).get('total',{}).get('value'))
for h in d.get('hits',{}).get('hits',[]):
    print('  ',h['_id'],'ns=',h['_source'].get('namespaces'),'type=',h['_source'].get('type'))
" 2>&1

echo "=== recent logins ==="
last -n 10 2>/dev/null
echo "--- ssh sessions ---"
who 2>/dev/null
echo "--- auth log tail (accepted) ---"
grep -i 'Accepted' /var/log/auth.log 2>/dev/null | tail -n 8

echo "=== kibana log: package/prebuilt mentions (last 20) ==="
grep -iE 'prebuilt|security_detection_engine|package.*install|upgrade' /var/log/kibana/kibana.log 2>/dev/null | tail -n 12 | cut -c1-400
echo DONE
