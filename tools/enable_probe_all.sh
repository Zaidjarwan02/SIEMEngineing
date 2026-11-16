#!/usr/bin/env bash
set +e
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'
for sp in default greencircle tkt; do
  echo "=== $sp all rules ==="
  curl -s --max-time 180 -u "$ADMIN" -H "$X" \
    "$KB/s/$sp/api/detection_engine/rules/_find?per_page=10000&page=1" \
    -o "/tmp/all_$sp.json" -w 'http=%{http_code} bytes=%{size_download} time=%{time_total}s\n'
  python3 - "$sp" <<'PY'
import json,sys
sp=sys.argv[1]
d=json.load(open(f'/tmp/all_{sp}.json'))
data=d.get('data',[])
ids=[r.get('id') for r in data]
print(' rules:',len(data),'unique ids:',len(set(ids)),'total:',d.get('total'))
PY
done
echo DONE
