#!/usr/bin/env bash
set +e
export LC_ALL=C
ES="http://127.0.0.1:9200"
ADMIN="elastic:<ADMIN_PASSWORD>"
for r in GreenCircle tkt; do
  echo "=== $r ==="
  curl -s --max-time 10 -u "$ADMIN" "$ES/_security/role/$r" | head -c 1200; echo
done
echo "=== last written restore payload present? ==="
ls -la /tmp/role_*restore*.json 2>/dev/null
echo DONE
