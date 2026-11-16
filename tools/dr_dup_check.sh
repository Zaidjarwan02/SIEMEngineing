#!/usr/bin/env bash
# Detect duplicate rule_ids in each space (caused by the interrupted install).
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "DUPLICATE ANALYSIS PER SPACE"
for sp in default grcico-com tkt-org; do
  echo "--- space $sp ---"
  rm -f /tmp/rules_$sp.json
  curl -s --max-time 300 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=10000" -o /tmp/rules_$sp.json
  python3 - "$sp" <<'PY'
import json,sys,collections
sp=sys.argv[1]
d=json.load(open(f'/tmp/rules_{sp}.json'))
data=d.get('data',[])
print('returned:',len(data),'total field:',d.get('total'))
by=collections.defaultdict(list)
for r in data:
    a=r.get('attributes',r)
    by[a.get('rule_id')].append((r.get('id'),a.get('version'),a.get('name'),a.get('immutable')))
dups={k:v for k,v in by.items() if len(v)>1}
print('unique rule_ids:',len(by),'rule_ids with duplicates:',len(dups))
for k,v in list(dups.items())[:10]:
    print('  rule_id',k)
    for x in v: print('     ',x)
PY
done

sec "END"
