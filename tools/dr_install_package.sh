#!/usr/bin/env bash
# Install the official prebuilt detection-rules package (packaged form of
# github.com/elastic/detection-rules) and report counts.
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
U="elastic:<ADMIN_PASSWORD>"
C="curl -s --max-time 60 -u $U"
K="curl -s --max-time 120 -u $U -H kbn-xsrf:true"
J='Content-Type: application/json'
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "INSTALL security_detection_engine PACKAGE"
$K -H "$J" -X POST "$KB/api/fleet/epm/packages/security_detection_engine" \
  -d '{"force":true}' | head -c 2000; echo

sec "INSTALLED PACKAGES"
$K "$KB/api/fleet/epm/packages?perPage=100" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for p in d.get('items',[]):
    print(' ',p.get('name'),p.get('version'),p.get('status'))
" 2>/dev/null

sec "PREBUILT RULES STATUS"
$K "$KB/internal/detection_engine/prebuilt_rules/status" | python3 -m json.tool 2>/dev/null | head -c 3000; echo

sec "PREBUILT RULES STATUS (api path)"
$K "$KB/api/detection_engine/rules/prepackaged/_status" | python3 -m json.tool 2>/dev/null | head -c 3000; echo

sec "KIBANA LOG TAIL (package install)"
tail -n 25 /var/log/kibana/kibana.log 2>/dev/null

sec "END"
