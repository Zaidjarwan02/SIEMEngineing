#!/usr/bin/env bash
# Verify the actual Kibana login flow for both tenant users.
set +e
export LC_ALL=C
KB="http://127.0.0.1:5601"
X='kbn-xsrf: true'

login() {
  user="$1"; pass="$2"; label="$3"
  jar="/tmp/cj_$user.txt"; rm -f "$jar"
  echo "================ $label ($user) ================"
  echo "--- login POST ---"
  curl -s -c "$jar" -b "$jar" -o /tmp/login_$user.out -w 'http=%{http_code}\n' \
    -H "$X" -H 'Content-Type: application/json' \
    -X POST "$KB/internal/security/login" \
    -d "{\"providerType\":\"basic\",\"providerName\":\"basic\",\"currentURL\":\"/\",\"params\":{\"username\":\"$user\",\"password\":\"$pass\"}}"
  head -c 400 /tmp/login_$user.out; echo
  echo "--- GET / ---"
  curl -s -b "$jar" -c "$jar" -o /dev/null -w 'http=%{http_code} redirect=%{redirect_url}\n' "$KB/"
  echo "--- GET /api/security/me ---"
  curl -s -b "$jar" "$KB/api/security/me" | head -c 500; echo
  echo "--- GET /api/spaces/space ---"
  curl -s -b "$jar" -H "$X" "$KB/api/spaces/space" | head -c 500; echo
  echo "--- GET /app/home ---"
  curl -s -b "$jar" -o /dev/null -w 'http=%{http_code} redirect=%{redirect_url}\n' "$KB/app/home"
  echo "--- GET /app/dashboards ---"
  curl -s -b "$jar" -o /dev/null -w 'http=%{http_code} redirect=%{redirect_url}\n' "$KB/app/dashboards"
  echo "--- GET /s/grcico-com/app/dashboards ---"
  curl -s -b "$jar" -o /dev/null -w 'http=%{http_code} redirect=%{redirect_url}\n' "$KB/s/grcico-com/app/dashboards"
  echo "--- GET /s/tkt-org/app/dashboards ---"
  curl -s -b "$jar" -o /dev/null -w 'http=%{http_code} redirect=%{redirect_url}\n' "$KB/s/tkt-org/app/dashboards"
  echo
}

login grc_user '<TENANT1_PASSWORD>' 'GREEN CIRCLE TENANT'
login tkt_user '<TENANT2_PASSWORD>' 'TKT TENANT'

echo "================ NEGATIVE LOGIN TESTS ================"
curl -s -o /dev/null -w 'grc_user wrong password -> http=%{http_code}\n' -H "$X" -H 'Content-Type: application/json' \
  -X POST "$KB/internal/security/login" \
  -d '{"providerType":"basic","providerName":"basic","currentURL":"/","params":{"username":"grc_user","password":"wrongpass"}}'
curl -s -o /dev/null -w 'unknown user -> http=%{http_code}\n' -H "$X" -H 'Content-Type: application/json' \
  -X POST "$KB/internal/security/login" \
  -d '{"providerType":"basic","providerName":"basic","currentURL":"/","params":{"username":"nosuchuser","password":"whatever"}}'
echo "done"
