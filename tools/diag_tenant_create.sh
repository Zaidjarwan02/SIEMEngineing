#!/usr/bin/env bash
set +e
ES="http://127.0.0.1:9200"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="greencircle_user:<TENANT1_PASSWORD>"
J='Content-Type: application/json'
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@"; }

echo -n "greencircle_user auto-create own data stream logs-newtest-greencircle: "
code -u "$TENANT1" -H "$J" -X POST "$ES/logs-newtest-greencircle/_doc?refresh=true" -d '{"@timestamp":"2026-11-11T10:00:00Z","m":"auto"}'; echo
echo -n "greencircle_user create plain index greencircle-plain-new: "
code -u "$TENANT1" -H "$J" -X PUT "$ES/greencircle-plain-new" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}'; echo

echo "cleanup"
curl -s -u "$ADMIN" -X DELETE "$ES/_data_stream/logs-newtest-greencircle" >/dev/null
curl -s -u "$ADMIN" -X DELETE "$ES/greencircle-plain-new" >/dev/null
echo done
