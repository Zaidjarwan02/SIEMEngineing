#!/usr/bin/env bash
# Sync prebuilt detection rules for ONE space to the installed package version.
#   usage: dr_sync_space.sh <space> <user:pass>
# Installs missing rules, upgrades outdated ones, then disables all enabled rules
# so every space has the same clean, disabled baseline.
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
SP="$1"; CRED="$2"
X='kbn-xsrf: true'; J='Content-Type: application/json'
sec() { printf '\n\n========== %s ==========\n' "$1"; }
stat() {
  curl -s --max-time 60 -u "$CRED" -H "$X" "$KB/s/$SP/internal/detection_engine/prebuilt_rules/status" \
    | python3 -c "import sys,json;d=json.load(sys.stdin).get('stats',{});print({k:d.get(k) for k in ('num_prebuilt_rules_installed','num_prebuilt_rules_to_install','num_prebuilt_rules_to_upgrade','num_prebuilt_rules_total_in_package')})" 2>/dev/null
}
count() {
  curl -s --max-time 90 -u "$CRED" -H "$X" "$KB/s/$SP/api/detection_engine/rules/_find?per_page=1" \
    | python3 -c "import sys,json;print('rules:',json.load(sys.stdin).get('total'))" 2>/dev/null
}

sec "SPACE $SP - BEFORE"
stat; count

sec "SPACE $SP - INSTALL MISSING RULES"
START=$(date +%s)
curl -s --max-time 500 -u "$CRED" -H "$X" -H "$J" \
  -X POST "$KB/s/$SP/internal/detection_engine/prebuilt_rules/installation/_perform" \
  -d '{"mode":"ALL_RULES"}' -o "/tmp/sync_install_$SP.json" -w 'http=%{http_code} time=%{time_total}s\n'
echo "elapsed=$(( $(date +%s)-START ))s"
python3 -c "import json;print('summary:',json.load(open('/tmp/sync_install_$SP.json')).get('summary'))" 2>/dev/null \
  || head -c 400 "/tmp/sync_install_$SP.json"

sec "SPACE $SP - UPGRADE OUTDATED RULES"
START=$(date +%s)
curl -s --max-time 500 -u "$CRED" -H "$X" -H "$J" \
  -X POST "$KB/s/$SP/internal/detection_engine/prebuilt_rules/upgrade/_perform" \
  -d '{"mode":"ALL_RULES"}' -o "/tmp/sync_upgrade_$SP.json" -w 'http=%{http_code} time=%{time_total}s\n'
echo "elapsed=$(( $(date +%s)-START ))s"
python3 -c "import json;print('summary:',json.load(open('/tmp/sync_upgrade_$SP.json')).get('summary'))" 2>/dev/null \
  || head -c 400 "/tmp/sync_upgrade_$SP.json"

sec "SPACE $SP - DISABLE ALL ENABLED RULES"
ids=$(curl -s --max-time 90 -u "$CRED" -H "$X" \
  "$KB/s/$SP/api/detection_engine/rules/_find?per_page=100&filter=alert.attributes.enabled:true" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',[]):
    print(r.get('attributes',r).get('rule_id'))
" 2>/dev/null)
if [ -z "$ids" ]; then echo "  none enabled"; else
  for rid in $ids; do
    echo -n "  disable $rid: "
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 -u "$CRED" -H "$X" -H "$J" \
      -X PATCH "$KB/s/$SP/api/detection_engine/rules" -d "{\"rule_id\":\"$rid\",\"enabled\":false}"
  done
fi

sec "SPACE $SP - AFTER"
stat; count
echo -n "enabled: "
curl -s --max-time 90 -u "$CRED" -H "$X" "$KB/s/$SP/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:true" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('total'))" 2>/dev/null
echo DONE
