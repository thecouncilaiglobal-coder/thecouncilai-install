#!/usr/bin/env bash
set -euo pipefail

# TheCouncilAI Bot - One-command installer (Ubuntu/Debian)
#
# What this does:
#  1) Installs Docker (if missing)
#  2) Creates /opt/thecouncilai/bot with a persistent data volume
#  3) Writes docker-compose.yml + .env
#  4) Runs FIRST-TIME setup interactively (asks ONLY for app email/password + pairing code)
#  5) Starts services in the background + auto-update (watchtower)

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

need_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "This installer currently supports Ubuntu/Debian (apt-get required)."
    exit 1
  fi
}

install_docker_if_missing() {
  if command -v docker >/dev/null 2>&1; then
    # Ensure daemon is running
    systemctl enable --now docker >/dev/null 2>&1 || true
    return
  fi

  echo "[1/5] Installing Docker..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable"     > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

ensure_dirs() {
  echo "[2/5] Preparing directories..."
  mkdir -p "$BOT_DIR/data"
  chmod 700 "$BOT_DIR" || true
  chmod 700 "$BOT_DIR/data" || true
}

write_env_file() {
  echo "[3/5] Writing configuration (.env)..."

  # If .env already exists, do NOT overwrite (safe re-run).
  if [ -f "$BOT_DIR/.env" ]; then
    echo "  - Existing $BOT_DIR/.env found; leaving as-is."
    return
  fi

  echo ""
  echo "Alpaca keys are required once. They are stored on THIS server only in $BOT_DIR/.env (chmod 600)."
  echo "If you prefer, you can paste dummy keys now and replace later."
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
}

write_compose_file() {
  echo "[4/5] Writing docker-compose.yml..."

  cat > "$BOT_DIR/docker-compose.yml" <<EOF
services:
  thecouncilai-bot:
    image: ${IMAGE}
    container_name: thecouncilai-bot
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./data:/data

  # Auto-update: pulls new :stable periodically and restarts only the bot container.
  watchtower:
    image: containrrr/watchtower:latest
    container_name: thecouncilai-watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 300 --cleanup thecouncilai-bot
EOF
}

ghcr_login_if_needed() {
  # If the image is public, no login is required.
  # If it's private, docker pull will fail; then we prompt for GHCR creds.
  if docker pull "$IMAGE" >/dev/null 2>&1; then
    return
  fi

  echo ""
  echo "Cannot pull $IMAGE without credentials."
  echo "Either:"
  echo "  A) Make the GHCR package PUBLIC (recommended for easiest customer install), OR"
  echo "  B) Provide GHCR credentials now."
  echo ""
  read -r -p "GHCR username (GitHub account/org): " GHCR_USER
  read -r -s -p "GHCR token (PAT with read:packages) (hidden): " GHCR_TOKEN
  echo ""
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
  docker pull "$IMAGE" >/dev/null
}

first_time_setup_interactive() {
  # If auth.json exists, bot will not prompt for email/password again.
  if [ -f "$BOT_DIR/data/auth.json" ]; then
    echo "  - Existing auth.json found; skipping first-time login/pairing."
    return
  fi

  echo ""
  echo "FIRST-TIME SETUP (interactive)"
  echo "You will be asked for:"
  echo "  1) TheCouncilAI app Email + Password"
  echo "  2) Pairing approval (QR/manual code) in the mobile app"
  echo ""
  cd "$BOT_DIR"
  docker compose run --rm -it thecouncilai-bot
}

start_services() {
  echo "[5/5] Starting services..."
  cd "$BOT_DIR"
  docker compose up -d

  echo ""
  echo "Installed."
  echo "Status:"
  echo "  cd $BOT_DIR"
  echo "  docker compose ps"
  echo ""
  echo "Logs:"
  echo "  docker logs -f thecouncilai-bot"
  echo "  docker logs -f thecouncilai-watchtower"
  echo ""
  echo "Stop/Start:"
  echo "  docker compose stop"
  echo "  docker compose start"
}

main() {
  need_root
  need_apt
  install_docker_if_missing
  ensure_dirs
  write_env_file
  write_compose_file
  ghcr_login_if_needed
  first_time_setup_interactive
  start_services
}

main "$@"
