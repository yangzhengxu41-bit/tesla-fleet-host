#!/bin/bash
set -e
cd /opt/teslamate
IP=82.156.53.116
if [ ! -f tls.crt ]; then
  openssl req -x509 -newkey rsa:2048 -keyout tls.key -out tls.crt -days 825 -nodes -subj "/CN=$IP" -addext "subjectAltName=IP:$IP"
  chmod 600 tls.key
fi
HASH=$(grep -A3 'basic_auth' Caddyfile | grep -o '\$2[aby]\$[^ ]*' | head -1)
if [ -z "$HASH" ]; then echo "HASH_NOT_FOUND"; exit 1; fi
cat > Caddyfile <<EOF
$IP:8443 {
  tls /etc/caddy/tls.crt /etc/caddy/tls.key
  basic_auth {
    yang $HASH
  }
  reverse_proxy teslamate:4000
}

$IP:8444 {
  tls /etc/caddy/tls.crt /etc/caddy/tls.key
  reverse_proxy grafana:3000
}
EOF
grep -q 'tls.crt' docker-compose.override.yml || cat >> docker-compose.override.yml <<'EOF'
  caddy:
    volumes:
      - ./tls.crt:/etc/caddy/tls.crt:ro
      - ./tls.key:/etc/caddy/tls.key:ro
EOF
docker compose up -d caddy
sleep 5
echo "LOCAL_8443_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8443/)"
echo "LOCAL_8444_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8444/login)"
echo FIX_DONE
