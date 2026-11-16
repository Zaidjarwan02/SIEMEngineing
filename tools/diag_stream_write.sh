#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
ADMIN="elastic:<ADMIN_PASSWORD>"
TENANT1="greencircle_user:<TENANT1_PASSWORD>"
TKT="tkt_user:<TENANT2_PASSWORD>"
J='Content-Type: application/json'
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@"; }
hits() { curl -s --max-time 10 "$@" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('hits',{}).get('total',{}).get('value','ERR'))" 2>/dev/null || echo ERR; }

echo "=== create data streams by indexing as admin ==="
for ds in logs-test-greencircle logs-test-tkt metrics-test-greencircle metrics-test-tkt; do
  echo -n "$ds: "; curl -s -u "$ADMIN" -H "$J" -X POST "$ES/$ds/_doc?refresh=true" -d "{\"tenant\":\"$ds\",\"message\":\"SECRET $ds\"}" | head -c 160; echo
done

echo
echo "=== tenant READ via own wildcard ==="
echo -n "greencircle logs own hits:    "; hits -u "$TENANT1" "$ES/logs-*-greencircle*/_search"
echo -n "greencircle metrics own hits: "; hits -u "$TENANT1" "$ES/metrics-*-greencircle*/_search"
echo -n "tkt logs own hits:    "; hits -u "$TKT" "$ES/logs-*-tkt*/_search"
echo -n "tkt metrics own hits: "; hits -u "$TKT" "$ES/metrics-*-tkt*/_search"

echo
echo "=== tenant READ other wildcard (must be 0) ==="
echo -n "greencircle logs tkt hits:    "; hits -u "$TENANT1" "$ES/logs-*-tkt*/_search"
echo -n "greencircle metrics tkt hits: "; hits -u "$TENANT1" "$ES/metrics-*-tkt*/_search"
echo -n "tkt logs greencircle hits:    "; hits -u "$TKT" "$ES/logs-*-greencircle*/_search"
echo -n "tkt metrics greencircle hits: "; hits -u "$TKT" "$ES/metrics-*-greencircle*/_search"

echo
echo "=== tenant WRITE to own data stream (expect 201) ==="
echo -n "greencircle -> logs-test-greencircle:    "; code -u "$TENANT1" -H "$J" -X POST "$ES/logs-test-greencircle/_doc?refresh=true" -d '{"m":"greencircle write"}'; echo
echo -n "greencircle -> metrics-test-greencircle: "; code -u "$TENANT1" -H "$J" -X POST "$ES/metrics-test-greencircle/_doc?refresh=true" -d '{"m":"greencircle write"}'; echo
echo -n "tkt -> logs-test-tkt:            "; code -u "$TKT" -H "$J" -X POST "$ES/logs-test-tkt/_doc?refresh=true" -d '{"m":"tkt write"}'; echo

echo
echo "=== tenant WRITE to other data stream (expect 403) ==="
echo -n "greencircle -> logs-test-tkt:            "; code -u "$TENANT1" -H "$J" -X POST "$ES/logs-test-tkt/_doc?refresh=true" -d '{"m":"should fail"}'; echo
echo -n "tkt -> logs-test-greencircle:    "; code -u "$TKT" -H "$J" -X POST "$ES/logs-test-greencircle/_doc?refresh=true" -d '{"m":"should fail"}'; echo

echo
echo "=== tenant WRITE to own custom index (greencircle-* / tkt-*) ==="
echo -n "greencircle -> greencircle-applog: "; code -u "$TENANT1" -H "$J" -X PUT "$ES/greencircle-applog" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}'; echo
echo -n "greencircle -> tkt-applog: "; code -u "$TENANT1" -H "$J" -X PUT "$ES/tkt-applog" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}'; echo
echo -n "greencircle -> random-index (must be 403): "; code -u "$TENANT1" -H "$J" -X PUT "$ES/random-index" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}'; echo

echo
echo "=== cleanup ==="
for ds in logs-test-greencircle logs-test-tkt metrics-test-greencircle metrics-test-tkt; do
  curl -s -u "$ADMIN" -X DELETE "$ES/_data_stream/$ds" >/dev/null
done
curl -s -u "$ADMIN" -X DELETE "$ES/greencircle-applog" >/dev/null
curl -s -u "$ADMIN" -X DELETE "$ES/tkt-applog" >/dev/null
curl -s -u "$ADMIN" -X DELETE "$ES/random-index" >/dev/null
echo "done"
