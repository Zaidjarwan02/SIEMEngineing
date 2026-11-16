#!/usr/bin/env bash
# Corrected tenant-isolation proof.
# Fixes two test-design artifacts from verify_isolation.sh:
#  1) Elasticsearch returns 200 (empty) for wildcard patterns that match no
#     concrete index, so we create real indices first.
#  2) Kibana /api/status is a global endpoint that ignores space privileges,
#     so space access is tested with space-scoped saved-object APIs.
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="greencircle_user:<TENANT1_PASSWORD>"
TKT="tkt_user:<TENANT2_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'
PASS=0; FAIL=0
res() { if [ "$1" = "$2" ]; then echo "PASS  $3 (expected $1, got $2)"; PASS=$((PASS+1));
        else echo "FAIL  $3 (expected $1, got $2)"; FAIL=$((FAIL+1)); fi; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@"; }
body() { curl -s --max-time 10 "$@"; }

echo "=========== SETUP CONCRETE TENANT INDICES ==========="
for idx in logs-test-greencircle logs-test-tkt metrics-test-greencircle metrics-test-tkt; do
  curl -s -u "$ADMIN" -H "$J" -X PUT "$ES/$idx" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' >/dev/null
  curl -s -u "$ADMIN" -H "$J" -X POST "$ES/$idx/_doc/1?refresh=true" -d "{\"tenant\":\"$idx\",\"message\":\"SECRET $idx\"}" >/dev/null
done
echo "created logs-/metrics- test indices for both tenants"

echo
echo "=========== ELASTICSEARCH: WILDCARD NAMESPACE ISOLATION ==========="
res 200 "$(code -u "$TENANT1" "$ES/logs-*-greencircle*/_search")" "greencircle_user searches own logs namespace"
res 403 "$(code -u "$TENANT1" "$ES/logs-*-tkt*/_search")"          "greencircle_user blocked from tkt logs namespace"
res 403 "$(code -u "$TENANT1" "$ES/metrics-*-tkt*/_search")"       "greencircle_user blocked from tkt metrics namespace"
res 403 "$(code -u "$TENANT1" "$ES/logs-*-greencircle*,logs-*-tkt*/_search")" "greencircle_user blocked when mixing both namespaces"
res 200 "$(code -u "$TKT" "$ES/logs-*-tkt*/_search")"          "tkt_user searches own logs namespace"
res 403 "$(code -u "$TKT" "$ES/logs-*-greencircle*/_search")"  "tkt_user blocked from greencircle logs namespace"
res 403 "$(code -u "$TKT" "$ES/metrics-*-greencircle*/_search")" "tkt_user blocked from greencircle metrics namespace"
res 403 "$(code -u "$TKT" "$ES/logs-*-greencircle*,logs-*-tkt*/_search")" "tkt_user blocked when mixing both namespaces"

echo
echo "=========== ELASTICSEARCH: CROSS-TENANT DOC CONTENT ==========="
G=$(body -u "$TENANT1" "$ES/logs-*-tkt*/_search?q=SECRET")
T=$(body -u "$TKT" "$ES/logs-*-greencircle*/_search?q=SECRET")
echo "greencircle_user tkt query result: $(echo "$G" | head -c 200)"
echo "tkt_user greencircle query result: $(echo "$T" | head -c 200)"
echo "$G" | grep -q 'logs-test-tkt' && { echo "FAIL  greencircle_user saw tkt document"; FAIL=$((FAIL+1)); } || { echo "PASS  greencircle_user saw no tkt document"; PASS=$((PASS+1)); }
echo "$T" | grep -q 'logs-test-greencircle' && { echo "FAIL  tkt_user saw greencircle document"; FAIL=$((FAIL+1)); } || { echo "PASS  tkt_user saw no greencircle document"; PASS=$((PASS+1)); }

echo
echo "=========== KIBANA: SPACE-SCOPED SAVED OBJECT ACCESS ==========="
# Listing dashboards in a space requires privileges in that space.
res 200 "$(code -u "$TENANT1" -H "$X" "$KB/s/greencircle/api/saved_objects/_find?type=dashboard")" "greencircle_user lists saved objects in own space"
res 403 "$(code -u "$TENANT1" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard")" "greencircle_user blocked from tkt space saved objects"
res 403 "$(code -u "$TENANT1" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard")" "greencircle_user blocked from default space saved objects"
res 200 "$(code -u "$TKT" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard")" "tkt_user lists saved objects in own space"
res 403 "$(code -u "$TKT" -H "$X" "$KB/s/greencircle/api/saved_objects/_find?type=dashboard")" "tkt_user blocked from greencircle space saved objects"
res 403 "$(code -u "$TKT" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard")" "tkt_user blocked from default space saved objects"

echo
echo "=========== KIBANA: SPACE LIST VISIBILITY ==========="
GS=$(body -u "$TENANT1" -H "$X" "$KB/api/spaces/space")
TS=$(body -u "$TKT" -H "$X" "$KB/api/spaces/space")
echo "greencircle_user spaces: $GS"
echo "tkt_user spaces: $TS"
echo "$GS" | grep -q '"id":"tkt"' && { echo "FAIL  greencircle_user sees tkt space"; FAIL=$((FAIL+1)); } || { echo "PASS  greencircle_user does not see tkt space"; PASS=$((PASS+1)); }
echo "$TS" | grep -q '"id":"greencircle"' && { echo "FAIL  tkt_user sees greencircle space"; FAIL=$((FAIL+1)); } || { echo "PASS  tkt_user does not see greencircle space"; PASS=$((PASS+1)); }

echo
echo "=========== CLEANUP ==========="
for idx in logs-test-greencircle logs-test-tkt metrics-test-greencircle metrics-test-tkt; do
  curl -s -u "$ADMIN" -X DELETE "$ES/$idx" >/dev/null
done
echo "removed test indices"

echo
echo "=========== RESULT ==========="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL ISOLATION TESTS PASSED" || echo "SOME TESTS FAILED"
