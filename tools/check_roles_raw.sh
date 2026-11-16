#!/usr/bin/env bash
set +e
ES="http://127.0.0.1:9200"
ADMIN="elastic:<ADMIN_PASSWORD>"
for r in GreenCircle tkt; do
  echo "=== raw role $r ==="
  curl -s -w '\nHTTP %{http_code}\n' --max-time 20 -u "$ADMIN" "$ES/_security/role/$r"
  echo
done
echo "=== tenant users ==="
curl -s -u "$ADMIN" "$ES/_security/user/grc_user" | head -c 800; echo
curl -s -u "$ADMIN" "$ES/_security/user/tkt_user" | head -c 800; echo
echo "=== temp files left from failed run ==="
ls -la /tmp/role_*.json 2>/dev/null
for f in /tmp/role_GreenCircle_new.json /tmp/role_tkt_new.json; do
  echo "--- $f ---"; head -c 600 "$f" 2>/dev/null; echo
done
echo DONE
