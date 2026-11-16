#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
ADMIN="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'
echo "=== index templates matching logs-* / metrics-* ==="
curl -s -u "$ADMIN" "$ES/_index_template?pretty" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d.get('index_templates',[]):
    n=t['name']
    p=t['index_template'].get('index_patterns',[])
    ds='DATA_STREAM' if t['index_template'].get('data_stream') else 'plain'
    if any(str(x).startswith(('logs','metrics')) for x in p):
        print(f'{n:45s} {ds:11s} {p}')
"
echo
echo "=== try creating a plain index logs-probe-greencircle as admin ==="
curl -s -u "$ADMIN" -H "$J" -X PUT "$ES/logs-probe-greencircle" -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' | head -c 400; echo
echo
echo "=== try indexing into logs-probe-greencircle without pre-creating (auto data stream) ==="
curl -s -u "$ADMIN" -H "$J" -X POST "$ES/logs-probe-greencircle/_doc" -d '{"message":"probe"}' | head -c 400; echo
echo
echo "=== data streams now ==="
curl -s -u "$ADMIN" "$ES/_data_stream/logs-probe*" | head -c 600; echo
echo
echo "=== cleanup ==="
curl -s -u "$ADMIN" -X DELETE "$ES/_data_stream/logs-probe-greencircle" | head -c 200; echo
curl -s -u "$ADMIN" -X DELETE "$ES/logs-probe-greencircle" | head -c 200; echo
