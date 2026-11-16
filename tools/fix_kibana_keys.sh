#!/usr/bin/env bash
# Add the three Kibana encryption keys required for alerts/detections/reporting,
# then restart Kibana and wait until it is available.
set -e
export LC_ALL=C
CFG=/etc/kibana/kibana.yml

if grep -q '^xpack\.encryptedSavedObjects\.encryptionKey:' "$CFG"; then
  echo "Encryption keys already present; not changing them."
else
  {
    echo ""
    echo "# --- MSSP provisioning: required encryption keys ---"
    echo "xpack.encryptedSavedObjects.encryptionKey: \"$(openssl rand -hex 32)\""
    echo "xpack.reporting.encryptionKey: \"$(openssl rand -hex 32)\""
    echo "xpack.security.encryptionKey: \"$(openssl rand -hex 32)\""
  } >> "$CFG"
  echo "Encryption keys appended to $CFG"
fi

echo "--- key lines (values masked) ---"
grep -E '^xpack\.(encryptedSavedObjects|reporting|security)\.encryptionKey:' "$CFG" | sed -E 's/(Key: ").{6}.*(")/\1******\2/'

echo "--- restarting kibana ---"
systemctl restart kibana

echo "--- waiting for kibana ---"
ok=0
for i in $(seq 1 80); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:5601/api/status || true)
  if [ "$code" = "200" ]; then ok=1; echo "Kibana available after $((i*3))s"; break; fi
  sleep 3
done
if [ "$ok" != "1" ]; then echo "WARNING: Kibana did not become available in time"; fi

echo "--- kibana status ---"
curl -s --max-time 10 http://127.0.0.1:5601/api/status | head -c 600
echo
echo "--- recent kibana errors ---"
grep -iE '"level":"(error|fatal)"' /var/log/kibana/kibana.log 2>/dev/null | tail -n 5
echo "DONE"
