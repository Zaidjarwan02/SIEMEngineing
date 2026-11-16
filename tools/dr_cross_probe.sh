#!/usr/bin/env bash
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
GRC="grc_user:<TENANT1_PASSWORD>"
TKT="tkt_user:<TENANT2_PASSWORD>"
X='kbn-xsrf: true'
probe() {
  name="$1"; cred="$2"; sp="$3"
  echo "=== $name -> space $sp ==="
  code=$(curl -s --max-time 45 -o /tmp/cross_${name}_${sp}.json -w '%{http_code}' \
    -u "$cred" -H "$X" "$KB/s/$sp/api/detection_engine/rules/_find?per_page=1")
  echo "HTTP $code"
  head -c 500 /tmp/cross_${name}_${sp}.json; echo
  echo
}
probe grc "$GRC" tkt-org
probe grc "$GRC" default
probe tkt "$TKT" grcico-com
probe tkt "$TKT" default
echo DONE
