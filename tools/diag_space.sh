#!/usr/bin/env bash
# Diagnostic: what does a cross-space saved-object query actually return?
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
GRC="grc_user:<TENANT1_PASSWORD>"
TKT="tkt_user:<TENANT2_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'

DASH='{"attributes":{"title":"DIAG-SECRET-DASHBOARD","hits":0,"description":"secret","panelsJSON":"[]","optionsJSON":"{\"useMargins\":true}","version":1,"timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{}"}},"references":[]}'

echo "=== create a dashboard in grcico-com as grc_user ==="
curl -s -u "$GRC" -H "$J" -H "$X" -X POST "$KB/s/grcico-com/api/saved_objects/dashboard" -d "$DASH" | head -c 300; echo
echo "=== create a dashboard in tkt-org as tkt_user ==="
curl -s -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/tkt-org/api/saved_objects/dashboard" -d "$DASH" | head -c 300; echo

echo
echo "=== grc_user reading its OWN space ==="
curl -s -u "$GRC" -H "$X" "$KB/s/grcico-com/api/saved_objects/_find?type=dashboard" | head -c 800; echo
echo "=== grc_user reading tkt-org space ==="
curl -s -u "$GRC" -H "$X" "$KB/s/tkt-org/api/saved_objects/_find?type=dashboard" | head -c 800; echo
echo "=== grc_user reading default space ==="
curl -s -u "$GRC" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard" | head -c 800; echo

echo
echo "=== tkt_user reading its OWN space ==="
curl -s -u "$TKT" -H "$X" "$KB/s/tkt-org/api/saved_objects/_find?type=dashboard" | head -c 800; echo
echo "=== tkt_user reading grcico-com space ==="
curl -s -u "$TKT" -H "$X" "$KB/s/grcico-com/api/saved_objects/_find?type=dashboard" | head -c 800; echo

echo
echo "=== grc_user GET a known tkt dashboard by id via tkt space ==="
TKTID=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/tkt-org/api/saved_objects/_find?type=dashboard&search=DIAG-SECRET" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['saved_objects'][0]['id'] if d.get('saved_objects') else '')" 2>/dev/null)
echo "tkt dashboard id: $TKTID"
curl -s -o /dev/null -w 'GET /s/tkt-org/.../<id> as grc_user -> %{http_code}\n' -u "$GRC" -H "$X" "$KB/s/tkt-org/api/saved_objects/dashboard/$TKTID"
curl -s -o /dev/null -w 'DELETE /s/tkt-org/.../<id> as grc_user -> %{http_code}\n' -u "$GRC" -H "$X" -X DELETE "$KB/s/tkt-org/api/saved_objects/dashboard/$TKTID"

echo
echo "=== cleanup ==="
for sp in grcico-com tkt-org; do
  ids=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/$sp/api/saved_objects/_find?type=dashboard&search=DIAG-SECRET" | python3 -c "import sys,json;print(' '.join(o['id'] for o in json.load(sys.stdin).get('saved_objects',[])))" 2>/dev/null)
  for id in $ids; do curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/s/$sp/api/saved_objects/dashboard/$id" >/dev/null; done
done
echo "done"
