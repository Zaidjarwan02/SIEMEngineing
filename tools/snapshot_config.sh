#!/usr/bin/env bash
set +e
export LC_ALL=C
echo "=== elasticsearch.yml security/TLS block ==="
grep -nE 'xpack\.security|ssl|keystore|truststore|verification_mode|http\.host|network\.host|discovery\.' /etc/elasticsearch/elasticsearch.yml
echo
echo "=== kibana.yml relevant block ==="
grep -nE '^server\.|^elasticsearch\.|^xpack\.|^logging\.' /etc/kibana/kibana.yml | sed -E 's/(password: ).*/\1<redacted>/'
echo
echo "=== kibana login page reachable ==="
curl -s -o /dev/null -w 'GET /login -> %{http_code}\n' http://127.0.0.1:5601/login
curl -s http://127.0.0.1:5601/api/status | python3 -c "import sys,json;d=json.load(sys.stdin);print('Kibana status:',d['status']['overall']['level'])" 2>/dev/null
echo
echo "=== detection engine status (as elastic) ==="
curl -s -u "elastic:<ADMIN_PASSWORD>" -H 'kbn-xsrf: true' http://127.0.0.1:5601/api/detection_engine/status
echo
echo "=== ES audit logging enabled? ==="
grep -nE 'audit' /etc/elasticsearch/elasticsearch.yml || echo "audit logging not configured"
echo
echo "=== elasticsearch package version ==="
dpkg-query -W -f='${Package} ${Version}\n' elasticsearch kibana 2>/dev/null
