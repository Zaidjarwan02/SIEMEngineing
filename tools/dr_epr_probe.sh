#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
U="elastic:<ADMIN_PASSWORD>"
C="curl -s --max-time 20 -u $U"
K="curl -s --max-time 30 -u $U -H kbn-xsrf:true"
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "ELASTIC PACKAGE REGISTRY CONNECTIVITY"
for u in https://epr.elastic.co/ https://epr.elastic.co/search?package=security_detection_engine https://artifacts.elastic.co/ https://registry.elastic.co/; do
  echo -n "$u -> "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 15 "$u"
done

sec "FLEET INSTALLED PACKAGES"
$K "$KB/api/fleet/epm/packages?perPage=100" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
except Exception as e:
    print('parse error',e); raise SystemExit
items=d.get('items',d if isinstance(d,list) else [])
print('count:',len(items))
for p in items:
    print(' ',p.get('name'),p.get('version'),p.get('status'))
" 2>/dev/null

sec "SECURITY_DETECTION_ENGINE PACKAGE DETAIL"
$K "$KB/api/fleet/epm/packages/security_detection_engine" | head -c 1500; echo

sec "FLEET PACKAGE INSTALL (dry probe: GET info endpoint)"
$K "$KB/api/fleet/epm/packages/security_detection_engine?prerelease=true" | head -c 800; echo

sec "DETECTION ENGINE HEALTH ENDPOINTS"
for ep in /api/detection_engine/health /internal/detection_engine/health/_cluster /api/detection_engine/rules/_find?per_page=1 /api/detection_engine/rules/prepackaged/_status; do
  echo -n "$ep -> "; curl -s -o /dev/null -w '%{http_code}\n' --max-time 15 -u "$U" -H 'kbn-xsrf: true' "$KB$ep"
done

sec "KIBANA VERSION + PLUGINS"
$K "$KB/api/status" | python3 -c "import sys,json;d=json.load(sys.stdin);print('version',d.get('version',{}).get('number'),'level',d.get('status',{}).get('overall',{}).get('level'))" 2>/dev/null

sec "END"
