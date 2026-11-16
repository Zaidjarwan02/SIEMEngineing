#!/usr/bin/env bash
# Remove duplicate prebuilt rules in grcico-com (keep one per rule_id).
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'
SP="grcico-com"

echo "=== fetching rules in $SP ==="
curl -s --max-time 300 -u "$ADMIN" -H "$X" \
  "$KB/s/$SP/api/detection_engine/rules/_find?per_page=10000" -o /tmp/rules_$SP.json

echo "=== computing duplicates to delete ==="
python3 - "$SP" <<'PY' > /tmp/dup_delete_ids.txt
import json,sys,collections
sp=sys.argv[1]
d=json.load(open(f'/tmp/rules_{sp}.json'))
by=collections.defaultdict(list)
for r in d.get('data',[]):
    a=r.get('attributes',r)
    by[a.get('rule_id')].append(r)
for rid,items in by.items():
    if len(items)<2: continue
    # keep the oldest (first created) and delete the rest
    items.sort(key=lambda r: (r.get('attributes',r).get('created_at',''), r.get('id')))
    for r in items[1:]:
        print(r['id'])
PY
N=$(wc -l < /tmp/dup_delete_ids.txt)
echo "duplicate objects to delete: $N"

echo "=== deleting ==="
OK=0; FAILED=0
while read -r id; do
  [ -z "$id" ] && continue
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -u "$ADMIN" -H "$X" \
    -X DELETE "$KB/s/$SP/api/detection_engine/rules?id=$id")
  if [ "$code" = "200" ]; then OK=$((OK+1)); else FAILED=$((FAILED+1)); echo "  delete $id -> $code"; fi
done < /tmp/dup_delete_ids.txt
echo "deleted=$OK failed=$FAILED"

echo "=== verify counts ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" \
  "$KB/s/$SP/api/detection_engine/rules/_find?per_page=1" \
  | python3 -c "import sys,json;print('total rules:',json.load(sys.stdin).get('total'))" 2>/dev/null
curl -s --max-time 60 -u "$ADMIN" -H "$X" \
  "$KB/s/$SP/internal/detection_engine/prebuilt_rules/status" \
  | python3 -c "import sys,json;d=json.load(sys.stdin).get('stats',{});print('status:',{k:d.get(k) for k in ('num_prebuilt_rules_installed','num_prebuilt_rules_to_install','num_prebuilt_rules_total_in_package')})" 2>/dev/null

echo "=== duplicate re-check ==="
curl -s --max-time 300 -u "$ADMIN" -H "$X" \
  "$KB/s/$SP/api/detection_engine/rules/_find?per_page=10000" -o /tmp/rules_${SP}_after.json
python3 - "$SP" <<'PY'
import json,sys,collections
sp=sys.argv[1]
d=json.load(open(f'/tmp/rules_{sp}_after.json'))
by=collections.defaultdict(int)
for r in d.get('data',[]):
    a=r.get('attributes',r); by[a.get('rule_id')]+=1
dups=[k for k,v in by.items() if v>1]
print('unique rule_ids:',len(by),'duplicates remaining:',len(dups))
PY

echo "=== END ==="
