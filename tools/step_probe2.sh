#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
X='kbn-xsrf: true'
J='Content-Type: application/json'
step() { echo "--- $1"; }

step "tkt spaces"
curl -s -o /tmp/t1.json -w 'http=%{http_code}\n' --max-time 20 -u "T2_user:<TENANT2_PASSWORD>" -H "$X" "$KB/api/spaces/space"
python3 -c "import json;print(sorted(s['id'] for s in json.load(open('/tmp/t1.json'))))" 2>/dev/null

step "tkt read default"
curl -s -o /dev/null -w 'http=%{http_code}\n' --max-time 20 -u "T2_user:<TENANT2_PASSWORD>" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard&per_page=1"

step "tkt write default (expect 403)"
curl -s -o /tmp/t3.json -w 'http=%{http_code}\n' --max-time 20 -u "T2_user:<TENANT2_PASSWORD>" -H "$X" -H "$J" -X POST "$KB/s/default/api/saved_objects/dashboard" -d '{"attributes":{"title":"probe-shared-default-write","hits":0,"description":"probe","panelsJSON":"[]","optionsJSON":"{}","version":1,"timeRestore":false}}'
head -c 200 /tmp/t3.json; echo

step "tkt write own (expect 200)"
curl -s -o /tmp/t4.json -w 'http=%{http_code}\n' --max-time 20 -u "T2_user:<TENANT2_PASSWORD>" -H "$X" -H "$J" -X POST "$KB/s/tkt/api/saved_objects/dashboard" -d '{"attributes":{"title":"probe-own-space-write","hits":0,"description":"probe","panelsJSON":"[]","optionsJSON":"{}","version":1,"timeRestore":false}}'
TID=$(python3 -c "import json;print(json.load(open('/tmp/t4.json')).get('id',''))" 2>/dev/null)
echo "   tkt dashboard id=$TID"

step "tkt cross greencircle (expect total 0 / 200)"
curl -s -o /tmp/t5.json -w 'http=%{http_code}\n' --max-time 20 -u "T2_user:<TENANT2_PASSWORD>" -H "$X" "$KB/s/greencircle/api/saved_objects/_find?type=dashboard&per_page=1"
python3 -c "import json;print('   total:',json.load(open('/tmp/t5.json')).get('total'))" 2>/dev/null

step "cleanup probe dashboards"
GID=$(python3 -c "import json;print(json.load(open('/tmp/s4.json')).get('id',''))" 2>/dev/null)
echo "   greencircle id=$GID"
[ -n "$GID" ] && curl -s -o /dev/null -w '   delete greencircle -> %{http_code}\n' --max-time 20 -u "T1_user:<TENANT1_PASSWORD>" -H "$X" -X DELETE "$KB/s/greencircle/api/saved_objects/dashboard/$GID"
[ -n "$TID" ] && curl -s -o /dev/null -w '   delete tkt -> %{http_code}\n' --max-time 20 -u "T2_user:<TENANT2_PASSWORD>" -H "$X" -X DELETE "$KB/s/tkt/api/saved_objects/dashboard/$TID"

step "residual probe objects in default (should be none)"
curl -s --max-time 20 -u "elastic:<ADMIN_PASSWORD>" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard&per_page=100&search=probe-shared-default-write" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('   total:',d.get('total'))" 2>/dev/null
echo DONE
