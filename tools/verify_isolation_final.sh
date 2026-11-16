#!/usr/bin/env bash
# FINAL tenant-isolation verification.
#
# Correct expectations:
#  * logs-* / metrics-* are data-stream templates, so test data is written to
#    real data streams (with @timestamp) instead of plain indices.
#  * Elasticsearch wildcard searches silently drop unauthorized indices; a
#    cross-tenant wildcard therefore returns 200 with 0 hits, not 403.
#  * Kibana saved-object _find is space-filtered and returns 200 with
#    total=0 for a space the user cannot access; direct GET/DELETE of a
#    known foreign object returns 403.
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
hits() { curl -s --max-time 10 "$@" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('hits',{}).get('total',{}).get('value','ERR'))" 2>/dev/null || echo ERR; }
total() { curl -s --max-time 10 "$@" | python3 -c "import sys,json;print(json.load(sys.stdin).get('total','ERR'))" 2>/dev/null || echo ERR; }
nonzero() { curl -s --max-time 10 "$@" | python3 -c "import sys,json;print('yes' if json.load(sys.stdin).get('total',0)>0 else 'no')" 2>/dev/null || echo ERR; }
cntq() { curl -s --max-time 10 "$@" | python3 -c "import sys,json;print(json.load(sys.stdin).get('count','ERR'))" 2>/dev/null || echo ERR; }
mkds() { curl -s -u "$ADMIN" -H "$J" -X POST "$ES/$1/_doc?refresh=true" -d "{\"@timestamp\":\"2026-11-11T09:00:00Z\",\"tenant\":\"$1\",\"run_id\":\"$RUN\",\"message\":\"SECRET $1\"}" >/dev/null; }
mkdash() { curl -s -u "$1" -H "$J" -H "$X" -X POST "$KB/s/$2/api/saved_objects/dashboard" -d "$DASH" >/dev/null; }

# Unique per-run marker so counts are independent of pre-existing tenant data.
RUN="isolation-$(date +%s)-$$"
Q="{\"query\":{\"term\":{\"run_id\":\"$RUN\"}}}"

DASH='{"attributes":{"title":"FINAL-ISOLATION-TEST","hits":0,"description":"","panelsJSON":"[]","optionsJSON":"{\"useMargins\":true}","version":1,"timeRestore":false,"kibanaSavedObjectMeta":{"searchSourceJSON":"{}"}},"references":[]}'

echo "=========== 1. SETUP REAL TENANT DATA STREAMS ==========="
for ds in logs-test-greencircle logs-test-tkt metrics-test-greencircle metrics-test-tkt; do mkds "$ds"; done
echo "created data streams: logs-/metrics- test-{greencircle,tkt}"
mkdash "$TENANT1" greencircle
mkdash "$TKT" tkt
echo "created one dashboard in each tenant space"

echo
echo "=========== 2. ELASTICSEARCH DATA ISOLATION ==========="
res 200 "$(code -u "$TENANT1" "$ES/logs-*-greencircle*/_search")" "greencircle_user READ own data stream"
res 0   "$(hits -u "$TENANT1" "$ES/logs-*-tkt*/_search")"       "greencircle_user READ other data stream (0 hits)"
res 201 "$(code -u "$TENANT1" -H "$J" -X POST "$ES/logs-test-greencircle/_doc?refresh=true" -d "{\"@timestamp\":\"2026-11-11T09:00:01Z\",\"tenant\":\"greencircle\",\"run_id\":\"$RUN\"}")" "greencircle_user WRITE own data stream"
res 403 "$(code -u "$TENANT1" -H "$J" -X POST "$ES/logs-test-tkt/_doc?refresh=true" -d "{\"@timestamp\":\"2026-11-11T09:00:01Z\",\"tenant\":\"tkt\",\"run_id\":\"$RUN\"}")" "greencircle_user WRITE other data stream (403)"
res 200 "$(code -u "$TKT" "$ES/logs-*-tkt*/_search")"       "tkt_user READ own data stream"
res 0   "$(hits -u "$TKT" "$ES/logs-*-greencircle*/_search")" "tkt_user READ other data stream (0 hits)"
res 201 "$(code -u "$TKT" -H "$J" -X POST "$ES/logs-test-tkt/_doc?refresh=true" -d "{\"@timestamp\":\"2026-11-11T09:00:01Z\",\"tenant\":\"tkt\",\"run_id\":\"$RUN\"}")" "tkt_user WRITE own data stream"
res 403 "$(code -u "$TKT" -H "$J" -X POST "$ES/logs-test-greencircle/_doc?refresh=true" -d "{\"@timestamp\":\"2026-11-11T09:00:01Z\",\"tenant\":\"greencircle\",\"run_id\":\"$RUN\"}")" "tkt_user WRITE other data stream (403)"

echo
echo "=========== 3. WILDCARD NAMESPACE ISOLATION (run-scoped hits) ==========="
res 2 "$(cntq -u "$TENANT1" -H "$J" "$ES/logs-*-greencircle*/_count" -d "$Q")"     "greencircle_user sees own logs (2 run docs)"
res 1 "$(cntq -u "$TENANT1" -H "$J" "$ES/metrics-*-greencircle*/_count" -d "$Q")"  "greencircle_user sees own metrics (1 run doc)"
res 0 "$(cntq -u "$TENANT1" -H "$J" "$ES/logs-*-tkt*/_count" -d "$Q")"             "greencircle_user sees 0 tkt logs"
res 0 "$(cntq -u "$TENANT1" -H "$J" "$ES/metrics-*-tkt*/_count" -d "$Q")"          "greencircle_user sees 0 tkt metrics"
res 2 "$(cntq -u "$TKT" -H "$J" "$ES/logs-*-tkt*/_count" -d "$Q")"             "tkt_user sees own logs (2 run docs)"
res 1 "$(cntq -u "$TKT" -H "$J" "$ES/metrics-*-tkt*/_count" -d "$Q")"          "tkt_user sees own metrics (1 run doc)"
res 0 "$(cntq -u "$TKT" -H "$J" "$ES/logs-*-greencircle*/_count" -d "$Q")"     "tkt_user sees 0 greencircle logs"
res 0 "$(cntq -u "$TKT" -H "$J" "$ES/metrics-*-greencircle*/_count" -d "$Q")"  "tkt_user sees 0 greencircle metrics"

echo
echo "=========== 4. ALERT-INDEX ISOLATION + SHARED DEFAULT ALERTS ==========="
res 403 "$(code -u "$TENANT1" "$ES/.internal.alerts-security.alerts-tkt-000001/_search")" "greencircle_user blocked from tkt alert index"
res 403 "$(code -u "$TKT" "$ES/.internal.alerts-security.alerts-greencircle-000001/_search")" "tkt_user blocked from greencircle alert index"
# Default is the shared general space: tenants may READ its alerts, never write.
res 200 "$(code -u "$TENANT1" "$ES/.internal.alerts-security.alerts-default-000001/_search")" "greencircle_user can READ shared default alerts"
res 200 "$(code -u "$TKT" "$ES/.internal.alerts-security.alerts-default-000001/_search")" "tkt_user can READ shared default alerts"
res 403 "$(code -u "$TENANT1" -H "$J" -X POST "$ES/.alerts-security.alerts-default/_doc?refresh=true" -d '{"test":"isolation"}')" "greencircle_user cannot WRITE shared default alerts"
res 403 "$(code -u "$TKT" -H "$J" -X POST "$ES/.alerts-security.alerts-default/_doc?refresh=true" -d '{"test":"isolation"}')" "tkt_user cannot WRITE shared default alerts"
res 200 "$(code -u "$TENANT1" -H "$J" -H "$X" -X POST "$KB/s/default/api/detection_engine/signals/search" -d '{"query":{"bool":{"must":[]}},"size":1}')" "greencircle_user can search default alerts in Kibana"
res 200 "$(code -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/default/api/detection_engine/signals/search" -d '{"query":{"bool":{"must":[]}},"size":1}')" "tkt_user can search default alerts in Kibana"

echo
echo "=========== 5. KIBANA SPACE LIST VISIBILITY ==========="
GS=$(curl -s -u "$TENANT1" -H "$X" "$KB/api/spaces/space")
TS=$(curl -s -u "$TKT" -H "$X" "$KB/api/spaces/space")
echo "greencircle_user spaces: $GS"
echo "tkt_user spaces: $TS"
# Policy: Default is the shared general space (read-only); own space is full access;
# the other tenant's space must never be visible.
echo "$GS" | grep -q '"id":"default"'    && { echo "PASS  greencircle_user sees shared default space"; PASS=$((PASS+1)); } || { echo "FAIL  greencircle_user cannot see shared default space"; FAIL=$((FAIL+1)); }
echo "$GS" | grep -q '"id":"tkt"'    && { echo "FAIL  greencircle_user sees tkt space"; FAIL=$((FAIL+1)); } || { echo "PASS  greencircle_user does not see tkt space"; PASS=$((PASS+1)); }
echo "$TS" | grep -q '"id":"default"'    && { echo "PASS  tkt_user sees shared default space"; PASS=$((PASS+1)); } || { echo "FAIL  tkt_user cannot see shared default space"; FAIL=$((FAIL+1)); }
echo "$TS" | grep -q '"id":"greencircle"' && { echo "FAIL  tkt_user sees greencircle space"; FAIL=$((FAIL+1)); } || { echo "PASS  tkt_user does not see greencircle space"; PASS=$((PASS+1)); }

echo
echo "=========== 6. KIBANA CROSS-SPACE SAVED OBJECTS ==========="
res yes "$(nonzero -u "$TENANT1" -H "$X" "$KB/s/greencircle/api/saved_objects/_find?type=dashboard")" "greencircle_user sees own dashboards (>0)"
res 0 "$(total -u "$TENANT1" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard")" "greencircle_user sees 0 tkt dashboards"
res 200 "$(code -u "$TENANT1" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard")" "greencircle_user can READ shared default space"
res yes "$(nonzero -u "$TENANT1" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard")" "greencircle_user sees shared default dashboards (>0)"
res yes "$(nonzero -u "$TKT" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard")" "tkt_user sees own dashboards (>0)"
res 0 "$(total -u "$TKT" -H "$X" "$KB/s/greencircle/api/saved_objects/_find?type=dashboard")" "tkt_user sees 0 greencircle dashboards"
res 200 "$(code -u "$TKT" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard")" "tkt_user can READ shared default space"
res yes "$(nonzero -u "$TKT" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard")" "tkt_user sees shared default dashboards (>0)"

echo
echo "=========== 7. KIBANA CROSS-SPACE WRITE / DIRECT ACCESS ==========="
res 200 "$(code -u "$TENANT1" -H "$J" -H "$X" -X POST "$KB/s/greencircle/api/saved_objects/dashboard" -d "$DASH")" "greencircle_user create dashboard in own space"
res 403 "$(code -u "$TENANT1" -H "$J" -H "$X" -X POST "$KB/s/tkt/api/saved_objects/dashboard" -d "$DASH")" "greencircle_user blocked creating dashboard in tkt space"
res 403 "$(code -u "$TENANT1" -H "$J" -H "$X" -X POST "$KB/s/default/api/saved_objects/dashboard" -d "$DASH")" "greencircle_user blocked creating dashboard in default space"
res 200 "$(code -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/tkt/api/saved_objects/dashboard" -d "$DASH")" "tkt_user create dashboard in own space"
res 403 "$(code -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/greencircle/api/saved_objects/dashboard" -d "$DASH")" "tkt_user blocked creating dashboard in greencircle space"
res 403 "$(code -u "$TKT" -H "$J" -H "$X" -X POST "$KB/s/default/api/saved_objects/dashboard" -d "$DASH")" "tkt_user blocked creating dashboard in default space"

TKTID=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard&search=FINAL-ISOLATION" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['saved_objects'][0]['id'] if d.get('saved_objects') else '')" 2>/dev/null)
res 403 "$(code -u "$TENANT1" -H "$X" "$KB/s/tkt/api/saved_objects/dashboard/$TKTID")" "greencircle_user direct GET of known tkt object"
res 403 "$(code -u "$TENANT1" -H "$X" -X DELETE "$KB/s/tkt/api/saved_objects/dashboard/$TKTID")" "greencircle_user direct DELETE of known tkt object"

# Read-only proof for the shared Default space: admin creates a disposable object,
# tenants must be unable to modify or delete it, then admin removes it.
DEFID=$(curl -s -u "$ADMIN" -H "$J" -H "$X" -X POST "$KB/s/default/api/saved_objects/dashboard" -d "$DASH" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
res 403 "$(code -u "$TENANT1" -H "$J" -H "$X" -X PUT "$KB/s/default/api/saved_objects/dashboard/$DEFID" -d "$DASH")" "greencircle_user cannot UPDATE shared default object"
res 403 "$(code -u "$TENANT1" -H "$X" -X DELETE "$KB/s/default/api/saved_objects/dashboard/$DEFID")" "greencircle_user cannot DELETE shared default object"
res 403 "$(code -u "$TKT" -H "$X" -X DELETE "$KB/s/default/api/saved_objects/dashboard/$DEFID")" "tkt_user cannot DELETE shared default object"
curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/s/default/api/saved_objects/dashboard/$DEFID" >/dev/null

echo
echo "=========== 8. PRIVILEGE ESCALATION CHECKS ==========="
res 403 "$(code -u "$TENANT1" "$ES/_security/user")" "greencircle_user cannot read security users"
res 403 "$(code -u "$TENANT1" "$ES/_cluster/health")" "greencircle_user cannot read cluster health"
res 403 "$(code -u "$TENANT1" -H "$J" -X PUT "$ES/random-admin-test" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}')" "greencircle_user cannot create index outside its namespace"
res 403 "$(code -u "$TKT" "$ES/_security/user")" "tkt_user cannot read security users"
res 403 "$(code -u "$TKT" "$ES/_cluster/health")" "tkt_user cannot read cluster health"
res 403 "$(code -u "$TKT" -H "$J" -X PUT "$ES/random-admin-test" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}')" "tkt_user cannot create index outside its namespace"

echo
echo "=========== 9. CLEANUP ==========="
for ds in logs-test-greencircle logs-test-tkt metrics-test-greencircle metrics-test-tkt; do
  curl -s -u "$ADMIN" -X DELETE "$ES/_data_stream/$ds" >/dev/null
done
curl -s -u "$ADMIN" -X DELETE "$ES/random-admin-test" >/dev/null
for sp in greencircle tkt; do
  ids=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/$sp/api/saved_objects/_find?type=dashboard&search=FINAL-ISOLATION" | python3 -c "import sys,json;print(' '.join(o['id'] for o in json.load(sys.stdin).get('saved_objects',[])))" 2>/dev/null)
  for id in $ids; do curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/s/$sp/api/saved_objects/dashboard/$id" >/dev/null; done
done
echo "removed all test data streams, indices and dashboards"

echo
echo "=========== RESULT ==========="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL ISOLATION TESTS PASSED" || echo "SOME TESTS FAILED"
