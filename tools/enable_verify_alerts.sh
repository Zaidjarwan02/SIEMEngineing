#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
GRC="grc_user:<TENANT1_PASSWORD>"
TKT="tkt_user:<TENANT2_PASSWORD>"
X='kbn-xsrf: true'
J='Content-Type: application/json'

echo "=== alert docs (admin, default) ==="
curl -s --max-time 30 -u "$ADMIN" -H "$J" -X POST "$ES/.internal.alerts-security.alerts-default*/_search?size=2" \
  -d '{"query":{"match_all":{}},"_source":["kibana.alert.rule.name","kibana.alert.rule.rule_id","@timestamp","kibana.alert.severity","kibana.alert.risk_score","kibana.space_ids"]}' \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('hits:',d.get('hits',{}).get('total',{}).get('value'))
for h in d.get('hits',{}).get('hits',[]):
    s=h['_source']
    print(' ',s.get('kibana.alert.rule.name'),'|',s.get('kibana.alert.rule.rule_id'),'|',s.get('@timestamp'),'|',s.get('kibana.alert.severity'),'|',s.get('kibana.space_ids'))
" 2>&1

echo
echo "=== direct ES alert index access per tenant ==="
for pair in "grc_user:<TENANT1_PASSWORD>" "tkt_user:<TENANT2_PASSWORD>"; do
  u=${pair%%:*}
  echo -n "  $u default internal count: "
  curl -s --max-time 30 -u "$pair" "$ES/.internal.alerts-security.alerts-default*/_count"; echo
  echo -n "  $u tkt internal direct: "
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 30 -u "$pair" "$ES/.internal.alerts-security.alerts-tkt-org-000001/_count"
  echo -n "  $u grc internal direct: "
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 30 -u "$pair" "$ES/.internal.alerts-security.alerts-grcico-com-000001/_count"
done

echo
echo "=== Kibana alerts search endpoints as grc_user in default ==="
for ep in "api/detection_engine/signals/search" "internal/detection_engine/signals/search"; do
  echo -n "  /s/default/$ep: "
  curl -s -o /tmp/alert_search.json -w '%{http_code}\n' --max-time 60 -u "$GRC" -H "$X" -H "$J" \
    -X POST "$KB/s/default/$ep" -d '{"query":{"query":"","language":"kuery"},"size":10}'
  head -c 200 /tmp/alert_search.json; echo
done

echo
echo "=== Security alerts UI page as tenants ==="
for pair in "grc_user:<TENANT1_PASSWORD>" "tkt_user:<TENANT2_PASSWORD>"; do
  u=${pair%%:*}
  echo -n "  $u /s/default/app/security/alerts: "
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 30 -u "$pair" -H "$X" "$KB/s/default/app/security/alerts"
done

echo
echo "=== tenant acknowledgement attempt (expect 403/404, read-only) ==="
curl -s -o /tmp/ack.json -w 'http=%{http_code}\n' --max-time 30 -u "$GRC" -H "$X" -H "$J" \
  -X POST "$KB/s/default/api/detection_engine/signals/status" -d '{"signal_ids":["x"],"status":"acknowledged"}'
head -c 200 /tmp/ack.json; echo
echo DONE
