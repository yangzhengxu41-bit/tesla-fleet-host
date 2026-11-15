#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
fi
swapon /swapfile 2>/dev/null || true
grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
apt-get update
apt-get install -y curl openssl
if ! command -v docker >/dev/null 2>&1; then
  apt-get install -y docker.io
fi
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y docker-compose-v2 || apt-get install -y docker-compose-plugin || true
fi
systemctl enable --now docker 2>/dev/null || service docker start || true
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{"registry-mirrors": ["https://mirror.ccs.tencentyun.com", "https://docker.m.daocloud.io", "https://docker.1ms.run", "https://dockerproxy.net"]}
EOF
systemctl restart docker 2>/dev/null || service docker restart || true
mkdir -p /opt/teslamate/import
cd /opt/teslamate
if [ ! -f .env ]; then
  cat > .env <<EOF
DBPASS=$(openssl rand -hex 16)
GRAFPASS=$(openssl rand -hex 12)
UIPASS=$(openssl rand -hex 12)
ENCRYPTION_KEY=$(openssl rand -hex 32)
EOF
  chmod 600 .env
fi
set -a; . ./.env; set +a
PUBIP=$(curl -s https://ifconfig.me || curl -s https://api.ipify.org)
echo "Public IP: $PUBIP"
read -p "Tesla Client ID: " CID
if [ -z "$CID" ]; then echo "CLIENT_ID_EMPTY"; exit 1; fi
UIHASH=$(docker run --rm caddy:2 caddy hash-password --plaintext "$UIPASS")
cat > Caddyfile <<EOF
$PUBIP:8443 {
  tls internal
  basic_auth {
    yang $UIHASH
  }
  reverse_proxy teslamate:4000
}

$PUBIP:8444 {
  tls internal
  reverse_proxy grafana:3000
}
EOF
cat > docker-compose.yml <<'EOF'
services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      - ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - DATABASE_USER=teslamate
      - DATABASE_PASS=${DBPASS}
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
    ports:
      - 127.0.0.1:4000:4000
    volumes:
      - ./import:/opt/app/import
    cap_drop:
      - all
  database:
    image: postgres:16-alpine
    restart: always
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=${DBPASS}
      - POSTGRES_DB=teslamate
    volumes:
      - teslamate-db:/var/lib/postgresql/data
  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    command: mosquitto -c /mosquitto-no-auth.conf
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data
  grafana:
    image: teslamate/grafana:latest
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=${DBPASS}
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFPASS}
    ports:
      - 127.0.0.1:3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana
  caddy:
    image: caddy:2
    restart: always
    ports:
      - 8443:8443
      - 8444:8444
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
      - caddy-config:/config
    depends_on:
      - teslamate
      - grafana
volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
  caddy-data:
  caddy-config:
EOF
cat > docker-compose.override.yml <<EOF
services:
  teslamate:
    environment:
      - TESLA_API_HOST=https://fleet-api.prd.cn.vn.cloud.tesla.cn
      - TESLA_AUTH_HOST=https://auth.tesla.cn
      - TESLA_AUTH_PATH=/oauth2/v3
      - TESLA_AUTH_CLIENT_ID=$CID
EOF
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 8443/tcp >/dev/null 2>&1 || true
ufw allow 8444/tcp >/dev/null 2>&1 || true
docker compose pull
docker compose up -d
sleep 20
docker compose ps
echo "================ ACCESS ================"
echo "TeslaMate: https://$PUBIP:8443  (user: yang / pass: $UIPASS)"
echo "Grafana:   https://$PUBIP:8444  (user: admin / pass: $GRAFPASS)"
echo "Passwords also stored in /opt/teslamate/.env"
echo "DONE"
