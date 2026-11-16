#!/usr/bin/env bash
# Verify detection-rule isolation between tenants and capture ownership/state.
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="greencircle_user:<TENANT1_PASSWORD>"
TKT="tkt_user:<TENANT2_PASSWORD>"
X='kbn-xsrf: true'
J='Content-Type: application/json'
PASS=0; FAIL=0
res() { if [ "$1" = "$2" ]; then echo "PASS  $3 (expected $1, got $2)"; PASS=$((PASS+1));
        else echo "FAIL  $3 (expected $1, got $2)"; FAIL=$((FAIL+1)); fi; }
total() { curl -s --max-time 90 "$@" | python3 -c "import sys,json;print(json.load(sys.stdin).get('total','ERR'))" 2>/dev/null || echo ERR; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 90 "$@"; }

echo "=========== RULE COUNTS (admin) ==========="
for sp in default greencircle tkt; do
  echo -n "space $sp: "; total -u "$ADMIN" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1"
done

echo
echo "=========== ENABLED RULE PER SPACE ==========="
for sp in default greencircle tkt; do
  echo "--- $sp ---"
  curl -s --max-time 90 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=10&filter=alert.attributes.enabled:true" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  enabled total:',d.get('total'))
for r in d.get('data',[]):
    a=r.get('attributes',r)
    print('   ',a.get('rule_id'),'|',a.get('name'),'| immutable',a.get('immutable'),'| created_by',a.get('created_by'))
" 2>/dev/null
done

echo
echo "=========== ENABLED-RULE ASSERTIONS ==========="
res 2062 "$(total -u "$ADMIN" -H "$X" "$KB/s/default/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true")" "default space has all 2062 rules enabled"
res 2062 "$(total -u "$ADMIN" -H "$X" "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true")" "greencircle space has all 2062 rules enabled"
res 2062 "$(total -u "$ADMIN" -H "$X" "$KB/s/tkt/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true")" "tkt space has all 2062 rules enabled"

echo
echo "=========== OWNERSHIP SAMPLE (tenant spaces) ==========="
for sp in greencircle tkt; do
  echo "--- $sp (first 3 rules) ---"
  curl -s --max-time 90 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=3" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',[]):
    a=r.get('attributes',r)
    print('   created_by=',a.get('created_by'),'updated_by=',a.get('updated_by'),'|',a.get('name')[:50])
" 2>/dev/null
done

echo
echo "=========== TENANT RULE ISOLATION ==========="
# Detection-rules API is stricter than saved objects: cross-tenant _find is 403.
# Default is the shared general space: tenants may READ its rules, never write.
res 200  "$(code -u "$TENANT1" -H "$X" "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=1")" "greencircle_user can query own space rules"
res 403  "$(code -u "$TENANT1" -H "$X" "$KB/s/tkt/api/detection_engine/rules/_find?per_page=1")"    "greencircle_user blocked from tkt rules (403)"
res 200  "$(code -u "$TENANT1" -H "$X" "$KB/s/default/api/detection_engine/rules/_find?per_page=1")"     "greencircle_user can READ shared default rules"
res 2062 "$(total -u "$TENANT1" -H "$X" "$KB/s/default/api/detection_engine/rules/_find?per_page=1")"    "greencircle_user sees shared default rule set (2062)"
res 200  "$(code -u "$TKT" -H "$X" "$KB/s/tkt/api/detection_engine/rules/_find?per_page=1")"    "tkt_user can query own space rules"
res 403  "$(code -u "$TKT" -H "$X" "$KB/s/greencircle/api/detection_engine/rules/_find?per_page=1")" "tkt_user blocked from greencircle rules (403)"
res 200  "$(code -u "$TKT" -H "$X" "$KB/s/default/api/detection_engine/rules/_find?per_page=1")"     "tkt_user can READ shared default rules"
res 2062 "$(total -u "$TKT" -H "$X" "$KB/s/default/api/detection_engine/rules/_find?per_page=1")"    "tkt_user sees shared default rule set (2062)"

# Direct access to a known tkt rule by internal id
TKTID=$(curl -s --max-time 90 -u "$ADMIN" -H "$X" "$KB/s/tkt/api/detection_engine/rules/_find?per_page=1" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null)
echo "known tkt rule id: $TKTID"
res 403 "$(code -u "$TENANT1" -H "$X" "$KB/s/tkt/api/detection_engine/rules?id=$TKTID")" "greencircle_user direct GET of tkt rule"
res 403 "$(code -u "$TENANT1" -H "$X" -X DELETE "$KB/s/tkt/api/detection_engine/rules?id=$TKTID")" "greencircle_user direct DELETE of tkt rule"
res 404 "$(code -u "$TENANT1" -H "$X" "$KB/s/default/api/detection_engine/rules?id=$TKTID")" "greencircle_user cannot fetch tkt rule via default space (404)"
res 403 "$(code -u "$TENANT1" -H "$J" -H "$X" -X POST "$KB/s/default/api/detection_engine/rules" -d '{"rule_id":"probe-default-write-0001","name":"probe","description":"p","risk_score":21,"severity":"low","type":"query","language":"kuery","query":"*","index":["logs-*"],"from":"now-9m","to":"now","interval":"5m","enabled":false}')" "greencircle_user cannot CREATE rule in shared default space (403)"

echo
echo "=========== RESULT ==========="
echo "PASS=$PASS FAIL=$FAIL"
