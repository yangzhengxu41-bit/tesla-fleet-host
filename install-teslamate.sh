#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
apt-get update -y
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
ufw allow 22/tcp || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw --force enable || true
mkdir -p /opt/teslamate
cd /opt/teslamate
DBPASS=$(openssl rand -hex 24)
GRAFPASS=$(openssl rand -hex 16)
ENCKEY=$(openssl rand -hex 32)
cat > .env <<EOF
DBPASS=$DBPASS
GRAFPASS=$GRAFPASS
ENCKEY=$ENCKEY
EOF
chmod 600 .env
cat > docker-compose.yml <<'EOF'
services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      - ENCRYPTION_KEY=${ENCKEY}
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
    ports:
      - 127.0.0.1:1883:1883
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data
  grafana:
    image: grafana/grafana:latest
    restart: always
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFPASS}
      - GF_AUTH_ANONYMOUS_ENABLED=false
    ports:
      - 127.0.0.1:3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana
  caddy:
    image: caddy:2
    restart: always
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
      - caddy-config:/config
volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
  caddy-data:
  caddy-config:
EOF
cat > Caddyfile <<'EOF'
teslamate.yangzhengxu.com {
  reverse_proxy teslamate:4000
}
grafana.yangzhengxu.com {
  reverse_proxy grafana:3000
}
EOF
docker compose up -d
echo "TESLAMATE_STACK_STARTED"
