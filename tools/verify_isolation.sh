#!/usr/bin/env bash
# Prove tenant isolation: data read/write and Kibana space boundaries.
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="T1_user:<TENANT1_PASSWORD>"
TKT="T2_user:<TENANT2_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'
PASS=0; FAIL=0
res() { # res <expected> <actual> <label>
  if [ "$1" = "$2" ]; then echo "PASS  $3 (expected $1, got $2)"; PASS=$((PASS+1));
  else echo "FAIL  $3 (expected $1, got $2)"; FAIL=$((FAIL+1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@"; }

echo "=========== SETUP TEST DATA ==========="
curl -s -u "$ADMIN" -H "$J" -X PUT "$ES/greencircle-isolation-test" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' >/dev/null
curl -s -u "$ADMIN" -H "$J" -X PUT "$ES/tkt-isolation-test" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' >/dev/null
curl -s -u "$ADMIN" -H "$J" -X POST "$ES/greencircle-isolation-test/_doc/1?refresh=true" -d '{"tenant":"greencircle","message":"TENANT1 SECRET DATA"}' >/dev/null
curl -s -u "$ADMIN" -H "$J" -X POST "$ES/tkt-isolation-test/_doc/1?refresh=true" -d '{"tenant":"tkt","message":"TKT SECRET DATA"}' >/dev/null
echo "created greencircle-isolation-test and tkt-isolation-test"

echo
echo "=========== ELASTICSEARCH DATA ISOLATION ==========="
res 200 "$(code -u "$TENANT1" "$ES/greencircle-isolation-test/_doc/1")" "T1_user READ own index"
res 403 "$(code -u "$TENANT1" "$ES/tkt-isolation-test/_doc/1")" "T1_user READ other tenant index"
res 201 "$(code -u "$TENANT1" -H "$J" -X POST "$ES/greencircle-isolation-test/_doc/2?refresh=true" -d '{"tenant":"greencircle","message":"greencircle wrote this"}')" "T1_user WRITE own index"
res 403 "$(code -u "$TENANT1" -H "$J" -X POST "$ES/tkt-isolation-test/_doc/2?refresh=true" -d '{"tenant":"tkt","message":"greencircle should not write"}')" "T1_user WRITE other tenant index"

res 200 "$(code -u "$TKT" "$ES/tkt-isolation-test/_doc/1")" "T2_user READ own index"
res 403 "$(code -u "$TKT" "$ES/greencircle-isolation-test/_doc/1")" "T2_user READ other tenant index"
res 201 "$(code -u "$TKT" -H "$J" -X POST "$ES/tkt-isolation-test/_doc/2?refresh=true" -d '{"tenant":"tkt","message":"tkt wrote this"}')" "T2_user WRITE own index"
res 403 "$(code -u "$TKT" -H "$J" -X POST "$ES/greencircle-isolation-test/_doc/2?refresh=true" -d '{"tenant":"greencircle","message":"tkt should not write"}')" "T2_user WRITE other tenant index"

res 403 "$(code -u "$TENANT1" "$ES/.internal.alerts-security.alerts-tkt-000001/_search")" "T1_user blocked from tkt alert index"
res 403 "$(code -u "$TKT" "$ES/.internal.alerts-security.alerts-greencircle-000001/_search")" "T2_user blocked from greencircle alert index"
res 200 "$(code -u "$TENANT1" "$ES/greencircle-isolation-test/_search?q=message:SECRET")" "T1_user can search own index"
res 403 "$(code -u "$TENANT1" "$ES/logs-*-tkt*/_search")" "T1_user blocked from tkt log namespace"
res 403 "$(code -u "$TKT" "$ES/logs-*-greencircle*/_search")" "T2_user blocked from greencircle log namespace"

echo
echo "=========== KIBANA SPACE ISOLATION ==========="
res 200 "$(code -u "$TENANT1" -H "$X" "$KB/s/greencircle/api/status")" "T1_user access own space"
res 403 "$(code -u "$TENANT1" -H "$X" "$KB/s/tkt/api/status")" "T1_user blocked from tkt space"
res 403 "$(code -u "$TENANT1" -H "$X" "$KB/s/default/api/status")" "T1_user blocked from default space"
res 200 "$(code -u "$TKT" -H "$X" "$KB/s/tkt/api/status")" "T2_user access own space"
res 403 "$(code -u "$TKT" -H "$X" "$KB/s/greencircle/api/status")" "T2_user blocked from greencircle space"
res 403 "$(code -u "$TKT" -H "$X" "$KB/s/default/api/status")" "T2_user blocked from default space"

echo
echo "=========== KIBANA WRITE ISOLATION (saved objects) ==========="
DASH='{"attributes":{"title":"Isolation Test Dashboard","hits":0,"description":"","panelsJSON":"[]","optionsJSON":"{\"useMargins\":true}","version":1,"timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{}"}},"references":[]}'
res 200 "$(code -u "$TENANT1" -H "$J" -H "$X" -X POST "$KB/s/greencircle/api/saved_objects/dashboard" -d "$DASH")" "T1_user create dashboard in own space"
res 403 "$(code -u "$TENANT1" -H "$J" -H "$X" -X POST "$KB/s/tkt/api/saved_objects/dashboard" -d "$DASH")" "T1_user blocked creating dashboard in tkt space"
res 200 "$(code -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/tkt/api/saved_objects/dashboard" -d "$DASH")" "T2_user create dashboard in own space"
res 403 "$(code -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/greencircle/api/saved_objects/dashboard" -d "$DASH")" "T2_user blocked creating dashboard in greencircle space"

echo
echo "=========== IDENTITY CHECK ==========="
echo "--- T1_user ---"; curl -s -u "$TENANT1" "$ES/_security/_authenticate"
echo; echo "--- T2_user ---"; curl -s -u "$TKT" "$ES/_security/_authenticate"
echo
echo "--- T1_user cannot read security users ---"; code -u "$TENANT1" "$ES/_security/user"; echo
echo "--- T1_user cannot read cluster health (no cluster priv) ---"; code -u "$TENANT1" "$ES/_cluster/health"; echo

echo
echo "=========== CLEANUP TEST OBJECTS ==========="
curl -s -u "$ADMIN" -X DELETE "$ES/greencircle-isolation-test" >/dev/null
curl -s -u "$ADMIN" -X DELETE "$ES/tkt-isolation-test" >/dev/null
for sp in greencircle tkt; do
  ids=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/$sp/api/saved_objects/_find?type=dashboard&search=Isolation%20Test" | python3 -c "import sys,json;print(' '.join(o['id'] for o in json.load(sys.stdin).get('saved_objects',[])))" 2>/dev/null)
  for id in $ids; do curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/s/$sp/api/saved_objects/dashboard/$id" >/dev/null; done
done
echo "removed test indices and dashboards"

echo
echo "=========== RESULT ==========="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL ISOLATION TESTS PASSED" || echo "SOME TESTS FAILED"
