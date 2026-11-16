#!/usr/bin/env bash
# Diagnostic: what does a cross-space saved-object query actually return?
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="T1_user:<TENANT1_PASSWORD>"
TKT="T2_user:<TENANT2_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'

DASH='{"attributes":{"title":"DIAG-SECRET-DASHBOARD","hits":0,"description":"secret","panelsJSON":"[]","optionsJSON":"{\"useMargins\":true}","version":1,"timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{}"}},"references":[]}'

echo "=== create a dashboard in greencircle as T1_user ==="
curl -s -u "$TENANT1" -H "$J" -H "$X" -X POST "$KB/s/greencircle/api/saved_objects/dashboard" -d "$DASH" | head -c 300; echo
echo "=== create a dashboard in tkt as T2_user ==="
curl -s -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/tkt/api/saved_objects/dashboard" -d "$DASH" | head -c 300; echo

echo
echo "=== T1_user reading its OWN space ==="
curl -s -u "$TENANT1" -H "$X" "$KB/s/greencircle/api/saved_objects/_find?type=dashboard" | head -c 800; echo
echo "=== T1_user reading tkt space ==="
curl -s -u "$TENANT1" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard" | head -c 800; echo
echo "=== T1_user reading default space ==="
curl -s -u "$TENANT1" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard" | head -c 800; echo

echo
echo "=== T2_user reading its OWN space ==="
curl -s -u "$TKT" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard" | head -c 800; echo
echo "=== T2_user reading greencircle space ==="
curl -s -u "$TKT" -H "$X" "$KB/s/greencircle/api/saved_objects/_find?type=dashboard" | head -c 800; echo

echo
echo "=== T1_user GET a known tkt dashboard by id via tkt space ==="
TKTID=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard&search=DIAG-SECRET" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['saved_objects'][0]['id'] if d.get('saved_objects') else '')" 2>/dev/null)
echo "tkt dashboard id: $TKTID"
curl -s -o /dev/null -w 'GET /s/tkt/.../<id> as T1_user -> %{http_code}\n' -u "$TENANT1" -H "$X" "$KB/s/tkt/api/saved_objects/dashboard/$TKTID"
curl -s -o /dev/null -w 'DELETE /s/tkt/.../<id> as T1_user -> %{http_code}\n' -u "$TENANT1" -H "$X" -X DELETE "$KB/s/tkt/api/saved_objects/dashboard/$TKTID"

echo
echo "=== cleanup ==="
for sp in greencircle tkt; do
  ids=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/$sp/api/saved_objects/_find?type=dashboard&search=DIAG-SECRET" | python3 -c "import sys,json;print(' '.join(o['id'] for o in json.load(sys.stdin).get('saved_objects',[])))" 2>/dev/null)
  for id in $ids; do curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/s/$sp/api/saved_objects/dashboard/$id" >/dev/null; done
done
echo "done"
