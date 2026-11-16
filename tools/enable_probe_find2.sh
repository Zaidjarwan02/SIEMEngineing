#!/usr/bin/env bash
set +e
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'

echo "=== fields only ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" \
  "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=3&fields=id,rule_id" | head -c 400; echo

echo "=== sort_field only ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" \
  "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=3&sort_field=rule_id&sort_order=asc" | head -c 400; echo

echo "=== plain page 1/2 ids ==="
for p in 1 2; do
  echo -n "page $p: "
  curl -s --max-time 60 -u "$ADMIN" -H "$X" \
    "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=3&page=$p" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print([r.get('rule_id') for r in d.get('data',[])])" 2>/dev/null
done
echo DONE
