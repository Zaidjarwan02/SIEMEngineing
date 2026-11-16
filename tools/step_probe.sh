#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
X='kbn-xsrf: true'
J='Content-Type: application/json'
t() { echo "--- $1"; shift; START=$(date +%s); "$@" ; echo "   [$(( $(date +%s)-START ))s]"; }

t "greencircle spaces" curl -s -o /tmp/s1.json -w 'http=%{http_code}\n' --max-time 20 -u "T1_user:<TENANT1_PASSWORD>" -H "$X" "$KB/api/spaces/space"
cat /tmp/s1.json | head -c 400; echo

t "greencircle read default" curl -s -o /tmp/s2.json -w 'http=%{http_code}\n' --max-time 20 -u "T1_user:<TENANT1_PASSWORD>" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard&per_page=1"
head -c 300 /tmp/s2.json; echo

t "greencircle write default" curl -s -o /tmp/s3.json -w 'http=%{http_code}\n' --max-time 20 -u "T1_user:<TENANT1_PASSWORD>" -H "$X" -H "$J" -X POST "$KB/s/default/api/saved_objects/dashboard" -d '{"attributes":{"title":"probe-shared-default-write","hits":0,"description":"probe","panelsJSON":"[]","optionsJSON":"{}","version":1,"timeRestore":false}}'
head -c 300 /tmp/s3.json; echo

t "greencircle write own" curl -s -o /tmp/s4.json -w 'http=%{http_code}\n' --max-time 20 -u "T1_user:<TENANT1_PASSWORD>" -H "$X" -H "$J" -X POST "$KB/s/greencircle/api/saved_objects/dashboard" -d '{"attributes":{"title":"probe-own-space-write","hits":0,"description":"probe","panelsJSON":"[]","optionsJSON":"{}","version":1,"timeRestore":false}}'
head -c 300 /tmp/s4.json; echo

t "greencircle cross tkt" curl -s -o /dev/null -w 'http=%{http_code}\n' --max-time 20 -u "T1_user:<TENANT1_PASSWORD>" -H "$X" "$KB/s/tkt/api/saved_objects/_find?type=dashboard&per_page=1"
echo DONE
