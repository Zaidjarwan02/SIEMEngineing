#!/usr/bin/env bash
# Probe: can a tenant user install/manage detection rules inside its own space?
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
ADMIN="elastic:<ADMIN_PASSWORD>"
GRC="grc_user:<TENANT1_PASSWORD>"
J='Content-Type: application/json'
X='kbn-xsrf: true'
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "WHICH RULE IS ENABLED IN DEFAULT"
curl -s -u "$ADMIN" -H "$X" \
  "$KB/s/default/api/detection_engine/rules/_find?per_page=5&filter=alert.attributes.enabled:true" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('total:',d.get('total'))
for r in d.get('data',[]):
    a=r.get('attributes',r)
    print(' ',a.get('name'),'| type',a.get('type'),'| enabled',a.get('enabled'),'| immutable',a.get('immutable'))
" 2>/dev/null

sec "API KEY COUNT (correct path)"
curl -s -u "$ADMIN" -H "$J" -X POST "$KB" >/dev/null 2>&1
curl -s -u "$ADMIN" -H "$J" -X POST "http://127.0.0.1:9200/_security/_query/api_key?pretty" \
  -d '{"query":{"match_all":{}},"size":0}' 2>/dev/null | head -c 400; echo

sec "TENANT: prebuilt_rules status in own space"
curl -s -o /dev/null -w 'grc_user status endpoint -> %{http_code}\n' --max-time 30 \
  -u "$GRC" -H "$X" "$KB/s/grcico-com/internal/detection_engine/prebuilt_rules/status"
curl -s --max-time 30 -u "$GRC" -H "$X" \
  "$KB/s/grcico-com/internal/detection_engine/prebuilt_rules/status" | head -c 400; echo

sec "TENANT: prebuilt install perform in own space"
curl -s -o /dev/null -w 'grc_user perform endpoint -> %{http_code}\n' --max-time 60 \
  -u "$GRC" -H "$X" -H "$J" -X POST \
  "$KB/s/grcico-com/internal/detection_engine/prebuilt_rules/installation/_perform" \
  -d '{"mode":"ALL_RULES"}'

sec "TENANT: create one custom query rule in own space"
RULE='{
  "rule_id":"probe-tenant-rule-0001",
  "name":"PROBE tenant rule",
  "description":"probe",
  "risk_score":21,
  "severity":"low",
  "type":"query",
  "language":"kuery",
  "query":"*",
  "index":["logs-*-greencircle*"],
  "from":"now-9m",
  "to":"now",
  "interval":"5m",
  "enabled":false
}'
curl -s -o /tmp/probe_rule.json -w 'grc_user create rule -> %{http_code}\n' --max-time 60 \
  -u "$GRC" -H "$X" -H "$J" -X POST "$KB/s/grcico-com/api/detection_engine/rules" -d "$RULE"
head -c 700 /tmp/probe_rule.json; echo

sec "TENANT: rule import endpoint"
printf '%s\n' "$RULE" > /tmp/probe_import.ndjson
curl -s -o /tmp/probe_import.json -w 'grc_user import rules -> %{http_code}\n' --max-time 60 \
  -u "$GRC" -H "$X" -X POST "$KB/s/grcico-com/api/detection_engine/rules/_import?overwrite=true" \
  --data-binary @/tmp/probe_import.ndjson
head -c 700 /tmp/probe_import.json; echo

sec "TENANT: list rules it created"
curl -s --max-time 30 -u "$GRC" -H "$X" \
  "$KB/s/grcico-com/api/detection_engine/rules/_find?per_page=5&filter=alert.attributes.enabled:false" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('total:',d.get('total'))" 2>/dev/null

sec "CLEANUP probe rule (admin)"
curl -s -u "$ADMIN" -H "$X" -X DELETE "$KB/s/grcico-com/api/detection_engine/rules?rule_id=probe-tenant-rule-0001" | head -c 200; echo

sec "END"
