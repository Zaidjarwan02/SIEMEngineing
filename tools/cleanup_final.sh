#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'

echo "=== unassigned shards ==="
curl -s -u "$ADMIN" "$ES/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason" | grep -i unassign

echo
echo "=== data views with ids in each tenant space ==="
for sp in grcico-com tkt-org; do
  echo "--- $sp ---"
  curl -s -u "$ADMIN" -H "$X" "$KB/s/$sp/api/data_views" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for v in d.get('data_view',[]):
    print(v.get('id'), '|', repr(v.get('name')), '|', v.get('title'), '| managed=', v.get('managed'))
" 2>/dev/null
done

echo
echo "=== delete leftover test index grc-admin-test ==="
curl -s -u "$ADMIN" -X DELETE "$ES/grc-admin-test"; echo

echo
echo "=== delete unnamed global logs-*/metrics-* data views inside tenant spaces ==="
for sp in grcico-com tkt-org; do
  ids=$(curl -s -u "$ADMIN" -H "$X" "$KB/s/$sp/api/data_views" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for v in d.get('data_view',[]):
    if not v.get('name') and v.get('title') in ('logs-*','metrics-*'):
        print(v['id'])
" 2>/dev/null)
  for id in $ids; do
    echo -n "  $sp delete $id: "
    curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/s/$sp/api/data_views/data_view/$id" | head -c 120; echo
  done
done

echo
echo "=== remaining data views ==="
for sp in grcico-com tkt-org; do
  echo "--- $sp ---"
  curl -s -u "$ADMIN" -H "$X" "$KB/s/$sp/api/data_views" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for v in d.get('data_view',[]):
    print(' ', repr(v.get('name')), '->', v.get('title'))
" 2>/dev/null
done

echo
echo "=== cluster health after cleanup ==="
curl -s -u "$ADMIN" "$ES/_cluster/health?pretty" | python3 -c "import sys,json;d=json.load(sys.stdin);print({k:d[k] for k in ('status','active_primary_shards','active_shards','unassigned_shards')})" 2>/dev/null
