#!/usr/bin/env bash
# Discovery for detection-rules import: current rules, license, network, tooling.
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
U="elastic:<ADMIN_PASSWORD>"
C="curl -s --max-time 15 -u $U"
K="curl -s --max-time 20 -u $U -H kbn-xsrf:true"
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "LICENSE"
$C "$ES/_license?pretty" | python3 -c "import sys,json;d=json.load(sys.stdin).get('license',{});print({k:d.get(k) for k in ('type','status','expiry_date_in_millis','max_resource_units')})" 2>/dev/null

sec "DETECTION ENGINE STATUS"
$K "$KB/api/detection_engine/status"; echo

sec "EXISTING RULES PER SPACE"
for sp in default grcico-com tkt-org; do
  echo -n "space $sp total rules: "
  $K "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('total','ERR'), d.get('page'), d.get('perPage'))" 2>/dev/null || echo ERR
done

sec "PREBUILT RULES STATUS (various endpoints)"
echo "--- /internal/detection_engine/prebuilt_rules/status ---"
$K "$KB/internal/detection_engine/prebuilt_rules/status" | head -c 1500; echo
echo "--- /api/detection_engine/rules/prepackaged ---"
$K "$KB/api/detection_engine/rules/prepackaged" | head -c 600; echo
echo "--- /api/detection_engine/prepackaged ---"
$K "$KB/api/detection_engine/prepackaged" | head -c 600; echo

sec "ALERT INDICES"
$C "$ES/_cat/indices/.alerts*,.internal.alerts*?v&h=index,docs.count,store.size" 2>/dev/null

sec "RULE SAVED OBJECTS PER SPACE"
for sp in default grcico-com tkt-org; do
  echo -n "space $sp alerting rules saved objects: "
  $K "$KB/s/$sp/api/saved_objects/_find?type=alert&per_page=1" | python3 -c "import sys,json;print(json.load(sys.stdin).get('total','ERR'))" 2>/dev/null || echo ERR
done

sec "NETWORK / INTERNET FROM VM"
echo -n "github.com https: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 12 https://github.com
echo -n "codeload.github.com: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 12 https://codeload.github.com/elastic/detection-rules/tar.gz/refs/heads/main
echo -n "raw.githubusercontent.com: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 12 https://raw.githubusercontent.com/elastic/detection-rules/main/README.md
echo -n "pypi.org: "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 12 https://pypi.org/simple/detection-rules/

sec "TOOLING"
echo -n "python3: "; python3 --version 2>&1
echo -n "pip3: "; python3 -m pip --version 2>&1 | head -n 1
echo -n "git: "; git --version 2>&1
echo -n "curl: "; curl --version 2>&1 | head -n 1
echo -n "unzip: "; command -v unzip || echo missing
echo -n "tar: "; tar --version 2>&1 | head -n 1
echo -n "jq: "; command -v jq || echo missing
echo -n "venv module: "; python3 -c "import venv;print('ok')" 2>&1
echo -n "pip index reachable: "; timeout 15 python3 -m pip download --no-deps --dest /tmp/piptest detection-rules 2>&1 | tail -n 3

sec "DISK FREE"
df -h / /tmp /var

sec "END"
