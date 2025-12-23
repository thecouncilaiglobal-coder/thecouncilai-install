#!/usr/bin/env bash
set -euo pipefail

BOT_IMAGE="ghcr.io/thecouncilaiglobal-coder/thecouncilai-bot:stable"

# Firebase web key secret değildir; burada sabit kalabilir.
FIREBASE_WEB_API_KEY="AIzaSyAuU8cfN4dWJepDfMYYVGufs5ANGxQOq5I"
FIREBASE_DATABASE_URL="https://thecouncilai-59a0f-default-rtdb.firebaseio.com"

APP_DIR="/opt/thecouncilai-bot"
DATA_DIR="${APP_DIR}/data"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash"
  exit 1
fi

echo "[1/6] Installing Docker (if missing)..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

echo "[2/6] Installing docker compose plugin (if missing)..."
if ! docker compose version >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y docker-compose-plugin
fi

echo "[3/6] Creating folders..."
mkdir -p "$DATA_DIR"
chmod 700 "$APP_DIR"
chmod 700 "$DATA_DIR"

echo "[4/6] Creating bot.env (Alpaca keys will be asked)..."
read -r -p "ALPACA_API_KEY: " ALPACA_API_KEY
read -r -s -p "ALPACA_SECRET_KEY (hidden): " ALPACA_SECRET_KEY
echo
read -r -p "ALPACA_TRADING_BASE_URL [https://paper-api.alpaca.markets]: " ALPACA_TRADING_BASE_URL
ALPACA_TRADING_BASE_URL="${ALPACA_TRADING_BASE_URL:-https://paper-api.alpaca.markets}"
read -r -p "ALPACA_DATA_BASE_URL [https://data.alpaca.markets]: " ALPACA_DATA_BASE_URL
ALPACA_DATA_BASE_URL="${ALPACA_DATA_BASE_URL:-https://data.alpaca.markets}"
read -r -p "ALPACA_DATA_FEED [iex]: " ALPACA_DATA_FEED
ALPACA_DATA_FEED="${ALPACA_DATA_FEED:-iex}"

cat > "${APP_DIR}/bot.env" <<EOF
FIREBASE_WEB_API_KEY=${FIREBASE_WEB_API_KEY}
FIREBASE_DATABASE_URL=${FIREBASE_DATABASE_URL}

ALPACA_API_KEY=${ALPACA_API_KEY}
ALPACA_SECRET_KEY=${ALPACA_SECRET_KEY}
ALPACA_TRADING_BASE_URL=${ALPACA_TRADING_BASE_URL}
ALPACA_DATA_BASE_URL=${ALPACA_DATA_BASE_URL}
ALPACA_DATA_FEED=${ALPACA_DATA_FEED}
EOF
chmod 600 "${APP_DIR}/bot.env"

echo "[5/6] Pulling image..."
docker pull "${BOT_IMAGE}"

echo "[6/6] First-time interactive setup (login + pairing)..."
echo "This will ask for your app Email/Password and show a QR/pair code."
echo "After you approve pairing in the mobile app, press CTRL+C once you see: listening_signals"
docker run --rm -it \
  --name thecouncilai-bot-setup \
  --env-file "${APP_DIR}/bot.env" \
  -v "${DATA_DIR}:/data" \
  "${BOT_IMAGE}"

echo "Creating docker-compose.yml (bot + auto-update watchtower)..."
cat > "${APP_DIR}/docker-compose.yml" <<EOF
services:
  thecouncilai-bot:
    image: ${BOT_IMAGE}
    container_name: thecouncilai-bot
    env_file:
      - ./bot.env
    volumes:
      - ./data:/data
    restart: unless-stopped

  watchtower:
    image: containrrr/watchtower
    container_name: thecouncilai-watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 300 --cleanup thecouncilai-bot
    restart: unless-stopped
EOF

echo "Starting services..."
cd "$APP_DIR"
docker compose up -d

echo "Done."
echo "Check logs: docker logs -f thecouncilai-bot"

