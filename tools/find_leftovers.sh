#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
J='Content-Type: application/json'; X='kbn-xsrf: true'

echo "=== data streams matching tenant patterns ==="
curl -s --max-time 30 -u "$ADMIN" "$ES/_data_stream/logs-*-tkt*,metrics-*-tkt*,logs-*-greencircle*,metrics-*-greencircle*?pretty" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for ds in d.get('data_streams',[]):
    print(' ',ds['name'],'indices:',[i['index_name'] for i in ds.get('indices',[])])
" 2>/dev/null

echo "=== doc counts for tkt patterns ==="
for p in 'logs-*-tkt*' 'metrics-*-tkt*' 'logs-*-greencircle*' 'metrics-*-greencircle*'; do
  echo -n "  $p: "
  curl -s --max-time 30 -u "$ADMIN" "$ES/$p/_count" | head -c 200; echo
done

echo "=== indices (not data streams) matching tkt ==="
curl -s --max-time 30 -u "$ADMIN" "$ES/_cat/indices/*tkt*?h=index,docs.count,store.size" | head -40

echo "=== tkt-org dashboards ==="
curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/s/tkt-org/api/saved_objects/_find?type=dashboard&per_page=100" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' total:',d.get('total'))
for o in d.get('saved_objects',[]):
    print('  ',o['id'],'|',o.get('attributes',{}).get('title'),'| updated',o.get('updated_at'))
" 2>/dev/null

echo "=== grcico-com dashboards ==="
curl -s --max-time 30 -u "$ADMIN" -H "$X" "$KB/s/grcico-com/api/saved_objects/_find?type=dashboard&per_page=100" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' total:',d.get('total'))
for o in d.get('saved_objects',[]):
    print('  ',o['id'],'|',o.get('attributes',{}).get('title'),'| updated',o.get('updated_at'))
" 2>/dev/null
echo DONE
