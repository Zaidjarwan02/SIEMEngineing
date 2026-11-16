#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
X='kbn-xsrf: true'

echo "=== installed package detail ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/api/fleet/epm/packages/security_detection_engine" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
i=d.get('item',d)
print(' version:',i.get('version'),'status:',i.get('status'),'installed_at:',i.get('installed_at'))
" 2>&1

echo "=== fleet settings ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/api/fleet/settings" | head -c 1200; echo

echo "=== kibana.yml fleet / package settings ==="
grep -nE 'fleet|package|upgrade' /etc/kibana/kibana.yml 2>/dev/null | sed -E 's/(password|key|token).*/\1: <redacted>/I'

echo "=== fleet background tasks ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/api/fleet/agent_policies?perPage=5" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(' agent policies:',d.get('total'))
for p in d.get('items',[])[:5]: print('  ',p.get('name'),'| packages:',[x.get('name')+':'+x.get('version','') for x in p.get('package_policies',[])][:5])
" 2>&1

echo "=== detection engine health ==="
curl -s --max-time 60 -u "$ADMIN" -H "$X" "$KB/api/detection_engine/health/_cluster" | head -c 500; echo

echo "=== package upgrade task log entries ==="
grep -iE 'packageUpgrade|package upgrade|UpgradePackages|upgrade.*package' /var/log/kibana/kibana.log 2>/dev/null | tail -n 6 | cut -c1-300
echo DONE
