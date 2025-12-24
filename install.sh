#!/usr/bin/env bash
set -euo pipefail

BOT_DIR="/opt/thecouncilai/bot"
IMAGE="ghcr.io/thecouncilaiglobal-coder/thecouncilai-bot:stable"

# Firebase (non-secret, but required)
FIREBASE_DATABASE_URL="https://thecouncilai-59a0f-default-rtdb.firebaseio.com"
FIREBASE_WEB_API_KEY="AIzaSyAuU8cfN4dWJepDfMYYVGufs5ANGxQOq5I"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
  fi
}

install_docker_if_missing() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi

  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

write_compose_files() {
  mkdir -p "$BOT_DIR/data"
  chmod 700 "$BOT_DIR"
  chmod 700 "$BOT_DIR/data"

  # Ask broker keys (required for live/paper trading)
  echo ""
  echo "Alpaca keys are required once (hidden input)."
  read -r -p "ALPACA_API_KEY: " ALPACA_API_KEY
  read -r -s -p "ALPACA_SECRET_KEY (hidden): " ALPACA_SECRET_KEY
  echo ""

  cat > "$BOT_DIR/.env" <<EOF
FIREBASE_WEB_API_KEY=$FIREBASE_WEB_API_KEY
FIREBASE_DATABASE_URL=$FIREBASE_DATABASE_URL

ALPACA_API_KEY=$ALPACA_API_KEY
ALPACA_SECRET_KEY=$ALPACA_SECRET_KEY
ALPACA_TRADING_BASE_URL=https://paper-api.alpaca.markets
ALPACA_DATA_BASE_URL=https://data.alpaca.markets
ALPACA_DATA_FEED=iex

EXECUTION_MODE=paper
LOG_LEVEL=INFO
EOF
  chmod 600 "$BOT_DIR/.env"

  cat > "$BOT_DIR/docker-compose.yml" <<'EOF'
services:
  thecouncilai-bot:
    image: ghcr.io/thecouncilaiglobal-coder/thecouncilai-bot:stable
    container_name: thecouncilai-bot
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./data:/data

  watchtower:
    image: containrrr/watchtower:latest
    container_name: thecouncilai-watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 300 --cleanup thecouncilai-bot
EOF
}

first_time_setup_interactive() {
  echo ""
  echo "Starting first-time login + pairing..."
  echo "You will be asked for TheCouncilAI app email/password, then pairing code approval in the mobile app."
  echo ""
  cd "$BOT_DIR"
  docker compose run --rm -it thecouncilai-bot
}

start_services() {
  cd "$BOT_DIR"
  docker compose up -d
  echo ""
  echo "Installed. Useful commands:"
  echo "  cd $BOT_DIR"
  echo "  docker compose ps"
  echo "  docker logs -f thecouncilai-bot"
  echo "  docker logs -f thecouncilai-watchtower"
}

main() {
  need_root
  install_docker_if_missing
  mkdir -p "$BOT_DIR"
  write_compose_files
  first_time_setup_interactive
  start_services
}

main "$@"
