#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
X='kbn-xsrf: true'
J='Content-Type: application/json'
t() { echo "--- $1"; shift; START=$(date +%s); "$@" ; echo "   [$(( $(date +%s)-START ))s]"; }

t "grc spaces" curl -s -o /tmp/s1.json -w 'http=%{http_code}\n' --max-time 20 -u "grc_user:<TENANT1_PASSWORD>" -H "$X" "$KB/api/spaces/space"
cat /tmp/s1.json | head -c 400; echo

t "grc read default" curl -s -o /tmp/s2.json -w 'http=%{http_code}\n' --max-time 20 -u "grc_user:<TENANT1_PASSWORD>" -H "$X" "$KB/s/default/api/saved_objects/_find?type=dashboard&per_page=1"
head -c 300 /tmp/s2.json; echo

t "grc write default" curl -s -o /tmp/s3.json -w 'http=%{http_code}\n' --max-time 20 -u "grc_user:<TENANT1_PASSWORD>" -H "$X" -H "$J" -X POST "$KB/s/default/api/saved_objects/dashboard" -d '{"attributes":{"title":"probe-shared-default-write","hits":0,"description":"probe","panelsJSON":"[]","optionsJSON":"{}","version":1,"timeRestore":false}}'
head -c 300 /tmp/s3.json; echo

t "grc write own" curl -s -o /tmp/s4.json -w 'http=%{http_code}\n' --max-time 20 -u "grc_user:<TENANT1_PASSWORD>" -H "$X" -H "$J" -X POST "$KB/s/grcico-com/api/saved_objects/dashboard" -d '{"attributes":{"title":"probe-own-space-write","hits":0,"description":"probe","panelsJSON":"[]","optionsJSON":"{}","version":1,"timeRestore":false}}'
head -c 300 /tmp/s4.json; echo

t "grc cross tkt" curl -s -o /dev/null -w 'http=%{http_code}\n' --max-time 20 -u "grc_user:<TENANT1_PASSWORD>" -H "$X" "$KB/s/tkt-org/api/saved_objects/_find?type=dashboard&per_page=1"
echo DONE
