#!/usr/bin/env bash
# Install prebuilt rules into DEFAULT space (correct API shape: mode=ALL_RULES).
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
U="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "PERFORM INSTALL (mode ALL_RULES) - timed"
START=$(date +%s)
curl -s --max-time 2400 -u "$U" -H 'kbn-xsrf: true' -H "$J" \
  -X POST "$KB/internal/detection_engine/prebuilt_rules/installation/_perform" \
  -d '{"mode":"ALL_RULES"}' -o /tmp/dr_install_default.json -w 'http=%{http_code} time=%{time_total}s\n'
END=$(date +%s)
echo "elapsed=$((END-START))s"
head -c 3000 /tmp/dr_install_default.json; echo

sec "STATUS AFTER INSTALL"
curl -s --max-time 60 -u "$U" -H 'kbn-xsrf: true' \
  "$KB/internal/detection_engine/prebuilt_rules/status" | python3 -m json.tool 2>/dev/null

sec "RULE COUNT IN DEFAULT SPACE"
curl -s --max-time 60 -u "$U" -H 'kbn-xsrf: true' \
  "$KB/s/default/api/detection_engine/rules/_find?per_page=1" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('total:',d.get('total'))" 2>/dev/null

sec "ENABLED RULES IN DEFAULT SPACE"
curl -s --max-time 60 -u "$U" -H 'kbn-xsrf: true' \
  "$KB/s/default/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('enabled total:',d.get('total'))" 2>/dev/null

sec "API KEY COUNT"
curl -s --max-time 30 -u "$U" -H "$J" -X POST \
  "http://127.0.0.1:9200/_security/api_key/_query?pretty" \
  -d '{"query":{"match_all":{}},"size":0}' 2>/dev/null | head -c 400; echo

sec "CLUSTER HEALTH + TASK COUNT"
curl -s --max-time 30 -u "$U" "http://127.0.0.1:9200/_cluster/health?pretty" | python3 -c "import sys,json;d=json.load(sys.stdin);print({k:d[k] for k in ('status','active_shards','unassigned_shards','number_of_pending_tasks')})" 2>/dev/null
curl -s --max-time 30 -u "$U" "http://127.0.0.1:9200/_tasks?group_by=parents&pretty" 2>/dev/null | head -c 200; echo

sec "END"
