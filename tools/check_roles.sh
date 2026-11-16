#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
ADMIN="elastic:<ADMIN_PASSWORD>"
for r in GreenCircle tkt; do
  echo "=== $r ==="
  curl -s --max-time 20 -u "$ADMIN" "$ES/_security/role/$r" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for a in d.get('applications',[]):
    print('  app:',a.get('application'),'privs:',a.get('privileges'),'res:',a.get('resources'))
print('  cluster:',d.get('cluster'))
print('  indices:',[i.get('names') for i in d.get('indices',[])])
" 2>&1
done
echo "=== spaces for tenants ==="
for u in grc_user tkt_user; do
  case "$u" in
    grc_user) p='<TENANT1_PASSWORD>' ;;
    tkt_user) p='<TENANT2_PASSWORD>' ;;
  esac
  echo -n "$u: "
  curl -s --max-time 20 -u "$u:$p" -H 'kbn-xsrf: true' "http://127.0.0.1:5601/api/spaces/space" \
    | python3 -c "import sys,json;print([s['id'] for s in json.load(sys.stdin)])" 2>&1
done
echo DONE
