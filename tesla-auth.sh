#!/bin/bash
set -u
CID=$(grep -o 'TESLA_AUTH_CLIENT_ID=[^ ]*' /opt/teslamate/docker-compose.override.yml | cut -d= -f2)
if [ -z "$CID" ]; then echo "CLIENT_ID_NOT_FOUND"; exit 1; fi
read -s -p "Client Secret: " SECRET; echo
read -p "Callback URL or code: " INPUT
CODE=$(echo "$INPUT" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
if [ -z "$CODE" ]; then CODE="$INPUT"; fi
PT=$(curl -s -X POST https://auth.tesla.cn/oauth2/v3/token -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "grant_type=client_credentials" --data-urlencode "client_id=$CID" --data-urlencode "client_secret=$SECRET" --data-urlencode "audience=https://fleet-api.prd.cn.vn.cloud.tesla.cn" --data-urlencode "scope=openid user_data vehicle_device_data vehicle_location vehicle_cmds" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')
if [ -n "$PT" ]; then
  PS=$(curl -s -o /tmp/partner.json -w '%{http_code}' -X POST https://fleet-api.prd.cn.vn.cloud.tesla.cn/api/1/partner_accounts -H "Authorization: Bearer $PT" -H 'Content-Type: application/json' -d '{"domain":"yangzhengxu.com"}')
  echo "PARTNER_REGISTER_HTTP=$PS"
else
  echo "PARTNER_TOKEN_FAILED"
fi
curl -s -X POST https://auth.tesla.cn/oauth2/v3/token -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "grant_type=authorization_code" --data-urlencode "client_id=$CID" --data-urlencode "client_secret=$SECRET" --data-urlencode "code=$CODE" --data-urlencode "redirect_uri=https://yangzhengxu.com/auth/callback" --data-urlencode "audience=https://fleet-api.prd.cn.vn.cloud.tesla.cn" > /tmp/token.json
python3 - <<'PYEOF'
import json
try:
    d=json.load(open('/tmp/token.json'))
except Exception:
    print("TOKEN_PARSE_ERROR"); raise SystemExit
if 'access_token' in d and 'refresh_token' in d:
    json.dump({'access_token':d['access_token'],'refresh_token':d['refresh_token']}, open('/opt/teslamate/tokens.json','w'))
    print("TOKENS_SAVED expires_in=", d.get('expires_in'))
else:
    print("TOKEN_EXCHANGE_FAILED:", d.get('error'), d.get('error_description'))
PYEOF
chmod 600 /opt/teslamate/tokens.json 2>/dev/null || true
echo DONE
