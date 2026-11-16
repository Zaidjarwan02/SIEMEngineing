#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'; X='kbn-xsrf: true'

echo "=== security-rule saved objects by namespace (ES) ==="
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.kibana*/_search?size=0" -d '{
 "query":{"term":{"type":"security-rule"}},
 "aggs":{"ns":{"terms":{"field":"namespaces","size":20}}}
}' | python3 -m json.tool 2>/dev/null | head -40

echo "=== total security-rule docs in .kibana* ==="
curl -s --max-time 30 -u "$ADMIN" "$ES/.kibana*/_count?q=type:security-rule" | head -c 300; echo

echo "=== kibana indices ==="
curl -s --max-time 30 -u "$ADMIN" "$ES/_cat/indices/.kibana*?h=index,health,docs.count,store.size" | head -20

echo "=== admin _find per space (status + body head) ==="
for sp in default grcico-com tkt-org; do
  echo "--- $sp ---"
  curl -s --max-time 60 -u "$ADMIN" -H "$X" -w '\nHTTP %{http_code}\n' \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1" | head -c 400; echo
done

echo "=== prebuilt status per space ==="
for sp in default grcico-com tkt-org; do
  echo -n "$sp: "
  curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/s/$sp/internal/detection_engine/prebuilt_rules/status" | head -c 300; echo
done

echo "=== kibana recent errors ==="
grep -iE 'error|fatal' /var/log/kibana/kibana.log 2>/dev/null | tail -n 15

echo "=== kibana process uptime ==="
ps -eo pid,etime,cmd | grep -E 'kibana|node' | grep -v grep | head -5
echo DONE
