#!/usr/bin/env bash
# Finish prebuilt-rules installation in each tenant space, as the tenant user.
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
GRC="grc_user:<TENANT1_PASSWORD>"
TKT="tkt_user:<TENANT2_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'
sec() { printf '\n\n========== %s ==========\n' "$1"; }

status() {
  sp="$1"
  curl -s --max-time 60 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/internal/detection_engine/prebuilt_rules/status" \
    | python3 -c "import sys,json;d=json.load(sys.stdin).get('stats',{});print({k:d.get(k) for k in ('num_prebuilt_rules_installed','num_prebuilt_rules_to_install','num_prebuilt_rules_total_in_package')})" 2>/dev/null
}
count() {
  sp="$1"
  curl -s --max-time 60 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1" \
    | python3 -c "import sys,json;print('total rules:',json.load(sys.stdin).get('total'))" 2>/dev/null
}
install_as() {
  user="$1"; sp="$2"; label="$3"
  echo "--- $label: $user -> $sp ---"
  START=$(date +%s)
  curl -s --max-time 2400 -u "$user" -H "$X" -H "$J" \
    -X POST "$KB/s/$sp/internal/detection_engine/prebuilt_rules/installation/_perform" \
    -d '{"mode":"ALL_RULES"}' -o "/tmp/inst_$sp.json" -w 'http=%{http_code} time=%{time_total}s\n'
  END=$(date +%s); echo "elapsed=$((END-START))s"
  python3 -c "
import json
d=json.load(open('/tmp/inst_$sp.json'))
print('summary:',d.get('summary'))
" 2>/dev/null || head -c 500 "/tmp/inst_$sp.json"
}

sec "BEFORE: grcico-com"
status grcico-com; count grcico-com

sec "INSTALL grcico-com AS grc_user"
install_as "$GRC" grcico-com "GreenCircle"

sec "AFTER: grcico-com"
status grcico-com; count grcico-com

sec "INSTALL tkt-org AS tkt_user"
install_as "$TKT" tkt-org "TKT"

sec "AFTER: tkt-org"
status tkt-org; count tkt-org

sec "RULE COUNTS ALL SPACES"
for sp in default grcico-com tkt-org; do
  echo -n "space $sp: "; count "$sp"
done

sec "ENABLED RULES PER SPACE"
for sp in default grcico-com tkt-org; do
  echo -n "space $sp enabled: "
  curl -s --max-time 60 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null
done

sec "API KEY COUNT"
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "http://127.0.0.1:9200/_security/_query/api_key?pretty" \
  -d '{"query":{"match_all":{}},"size":0}' 2>/dev/null | head -c 200; echo

sec "CLUSTER HEALTH"
curl -s --max-time 30 -u "$ADMIN" "http://127.0.0.1:9200/_cluster/health?pretty" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print({k:d[k] for k in ('status','active_shards','unassigned_shards','number_of_pending_tasks')})" 2>/dev/null

sec "END"
