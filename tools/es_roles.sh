#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"; KB="http://127.0.0.1:5601"
U="elastic:<ADMIN_PASSWORD>"
C="curl -s --max-time 10 -u $U"
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "ROLE GreenCircle"
$C "$ES/_security/role/GreenCircle?pretty"
sec "ROLE tkt"
$C "$ES/_security/role/tkt?pretty"

sec "USER grc_user"
$C "$ES/_security/user/grc_user?pretty"
sec "USER tkt_user"
$C "$ES/_security/user/tkt_user?pretty"

sec "KIBANA SPACES"
curl -s --max-time 10 -u "$U" -H 'kbn-xsrf: true' "$KB/api/spaces/space"
echo
sec "KIBANA FEATURES (security)"
curl -s --max-time 10 -u "$U" -H 'kbn-xsrf: true' "$KB/api/features" | head -c 1500
echo
sec "SAVED OBJECTS all types"
curl -s --max-time 10 -u "$U" -H 'kbn-xsrf: true' "$KB/api/saved_objects/_find?per_page=100" | head -c 3000
echo
sec "ELASTICSEARCH LOG (main, last 60)"
ls /var/log/elasticsearch/
tail -n 60 /var/log/elasticsearch/grcico.SIEM.log 2>/dev/null || tail -n 60 /var/log/elasticsearch/*.log 2>/dev/null | grep -v '^==>'
sec "KIBANA LOG errors (last 30)"
grep -iE '"level":"(error|fatal)"|error' /var/log/kibana/kibana.log 2>/dev/null | tail -n 30
sec "END"
