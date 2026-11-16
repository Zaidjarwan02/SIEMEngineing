#!/usr/bin/env bash
# Prove tenant isolation: data read/write and Kibana space boundaries.
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
GRC="grc_user:<TENANT1_PASSWORD>"
TKT="tkt_user:<TENANT2_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'
PASS=0; FAIL=0
res() { # res <expected> <actual> <label>
  if [ "$1" = "$2" ]; then echo "PASS  $3 (expected $1, got $2)"; PASS=$((PASS+1));
  else echo "FAIL  $3 (expected $1, got $2)"; FAIL=$((FAIL+1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@"; }

echo "=========== SETUP TEST DATA ==========="
curl -s -u "$ADMIN" -H "$J" -X PUT "$ES/grc-isolation-test" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' >/dev/null
curl -s -u "$ADMIN" -H "$J" -X PUT "$ES/tkt-isolation-test" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' >/dev/null
curl -s -u "$ADMIN" -H "$J" -X POST "$ES/grc-isolation-test/_doc/1?refresh=true" -d '{"tenant":"greencircle","message":"GRC SECRET DATA"}' >/dev/null
curl -s -u "$ADMIN" -H "$J" -X POST "$ES/tkt-isolation-test/_doc/1?refresh=true" -d '{"tenant":"tkt","message":"TKT SECRET DATA"}' >/dev/null
echo "created grc-isolation-test and tkt-isolation-test"

echo
echo "=========== ELASTICSEARCH DATA ISOLATION ==========="
res 200 "$(code -u "$GRC" "$ES/grc-isolation-test/_doc/1")" "grc_user READ own index"
res 403 "$(code -u "$GRC" "$ES/tkt-isolation-test/_doc/1")" "grc_user READ other tenant index"
res 201 "$(code -u "$GRC" -H "$J" -X POST "$ES/grc-isolation-test/_doc/2?refresh=true" -d '{"tenant":"greencircle","message":"grc wrote this"}')" "grc_user WRITE own index"
res 403 "$(code -u "$GRC" -H "$J" -X POST "$ES/tkt-isolation-test/_doc/2?refresh=true" -d '{"tenant":"tkt","message":"grc should not write"}')" "grc_user WRITE other tenant index"

res 200 "$(code -u "$TKT" "$ES/tkt-isolation-test/_doc/1")" "tkt_user READ own index"
res 403 "$(code -u "$TKT" "$ES/grc-isolation-test/_doc/1")" "tkt_user READ other tenant index"
res 201 "$(code -u "$TKT" -H "$J" -X POST "$ES/tkt-isolation-test/_doc/2?refresh=true" -d '{"tenant":"tkt","message":"tkt wrote this"}')" "tkt_user WRITE own index"
res 403 "$(code -u "$TKT" -H "$J" -X POST "$ES/grc-isolation-test/_doc/2?refresh=true" -d '{"tenant":"greencircle","message":"tkt should not write"}')" "tkt_user WRITE other tenant index"

res 403 "$(code -u "$GRC" "$ES/.internal.alerts-security.alerts-tkt-org-000001/_search")" "grc_user blocked from tkt alert index"
res 403 "$(code -u "$TKT" "$ES/.internal.alerts-security.alerts-grcico-com-000001/_search")" "tkt_user blocked from grc alert index"
res 200 "$(code -u "$GRC" "$ES/grc-isolation-test/_search?q=message:SECRET")" "grc_user can search own index"
res 403 "$(code -u "$GRC" "$ES/logs-*-tkt*/_search")" "grc_user blocked from tkt log namespace"
res 403 "$(code -u "$TKT" "$ES/logs-*-greencircle*/_search")" "tkt_user blocked from grc log namespace"

echo
echo "=========== KIBANA SPACE ISOLATION ==========="
res 200 "$(code -u "$GRC" -H "$X" "$KB/s/grcico-com/api/status")" "grc_user access own space"
res 403 "$(code -u "$GRC" -H "$X" "$KB/s/tkt-org/api/status")" "grc_user blocked from tkt space"
res 403 "$(code -u "$GRC" -H "$X" "$KB/s/default/api/status")" "grc_user blocked from default space"
res 200 "$(code -u "$TKT" -H "$X" "$KB/s/tkt-org/api/status")" "tkt_user access own space"
res 403 "$(code -u "$TKT" -H "$X" "$KB/s/grcico-com/api/status")" "tkt_user blocked from grc space"
res 403 "$(code -u "$TKT" -H "$X" "$KB/s/default/api/status")" "tkt_user blocked from default space"

echo
echo "=========== KIBANA WRITE ISOLATION (saved objects) ==========="
DASH='{"attributes":{"title":"Isolation Test Dashboard","hits":0,"description":"","panelsJSON":"[]","optionsJSON":"{\"useMargins\":true}","version":1,"timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{}"}},"references":[]}'
res 200 "$(code -u "$GRC" -H "$J" -H "$X" -X POST "$KB/s/grcico-com/api/saved_objects/dashboard" -d "$DASH")" "grc_user create dashboard in own space"
res 403 "$(code -u "$GRC" -H "$J" -H "$X" -X POST "$KB/s/tkt-org/api/saved_objects/dashboard" -d "$DASH")" "grc_user blocked creating dashboard in tkt space"
res 200 "$(code -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/tkt-org/api/saved_objects/dashboard" -d "$DASH")" "tkt_user create dashboard in own space"
res 403 "$(code -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/grcico-com/api/saved_objects/dashboard" -d "$DASH")" "tkt_user blocked creating dashboard in grc space"

echo
echo "=========== IDENTITY CHECK ==========="
echo "--- grc_user ---"; curl -s -u "$GRC" "$ES/_security/_authenticate"
echo; echo "--- tkt_user ---"; curl -s -u "$TKT" "$ES/_security/_authenticate"
echo
echo "--- grc_user cannot read security users ---"; code -u "$GRC" "$ES/_security/user"; echo
echo "--- grc_user cannot read cluster health (no cluster priv) ---"; code -u "$GRC" "$ES/_cluster/health"; echo

echo
echo "=========== CLEANUP TEST OBJECTS ==========="
curl -s -u "$ADMIN" -X DELETE "$ES/grc-isolation-test" >/dev/null
curl -s -u "$ADMIN" -X DELETE "$ES/tkt-isolation-test" >/dev/null
for sp in grcico-com tkt-org; do
  ids=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/$sp/api/saved_objects/_find?type=dashboard&search=Isolation%20Test" | python3 -c "import sys,json;print(' '.join(o['id'] for o in json.load(sys.stdin).get('saved_objects',[])))" 2>/dev/null)
  for id in $ids; do curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/s/$sp/api/saved_objects/dashboard/$id" >/dev/null; done
done
echo "removed test indices and dashboards"

echo
echo "=========== RESULT ==========="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL ISOLATION TESTS PASSED" || echo "SOME TESTS FAILED"
