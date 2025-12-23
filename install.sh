#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/thecouncilai/bot"
DATA_DIR="${APP_DIR}/data"
ENV_FILE="${APP_DIR}/bot.env"
COMPOSE_FILE="${APP_DIR}/docker-compose.yml"

IMAGE="ghcr.io/thecouncilaiglobal-coder/thecouncilai-bot:stable"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root: sudo bash install.sh"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

install_docker_if_needed() {
  if have_cmd docker; then
    echo "[OK] Docker is installed."
    return
  fi
  echo "[INFO] Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker || true
  echo "[OK] Docker installed."
}

install_compose_if_needed() {
  # Newer Docker installs include compose plugin.
  if docker compose version >/dev/null 2>&1; then
    echo "[OK] Docker Compose plugin is available."
    return
  fi
  echo "[INFO] Installing docker compose plugin..."
  apt-get update -y
  apt-get install -y docker-compose-plugin
  echo "[OK] Docker Compose plugin installed."
}

write_compose() {
  mkdir -p "${APP_DIR}" "${DATA_DIR}"

  cat > "${COMPOSE_FILE}" <<YAML
services:
  thecouncilai-bot:
    image: ${IMAGE}
    container_name: thecouncilai-bot
    env_file:
      - bot.env
    volumes:
      - ${DATA_DIR}:/data
    restart: unless-stopped
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

  watchtower:
    image: containrrr/watchtower:latest
    container_name: thecouncilai-watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --label-enable --interval 300 --cleanup
    restart: unless-stopped
YAML

  echo "[OK] docker-compose.yml written to ${COMPOSE_FILE}"
}

prompt_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    echo "[OK] bot.env already exists at ${ENV_FILE}"
    return
  fi

  echo ""
  echo "=== TheCouncilAI Bot - Configuration ==="
  echo "These values will be saved to: ${ENV_FILE}"
  echo ""

  read -r -p "FIREBASE_DATABASE_URL (e.g. https://xxxx-default-rtdb.firebaseio.com): " FIREBASE_DATABASE_URL
  read -r -p "FIREBASE_WEB_API_KEY: " FIREBASE_WEB_API_KEY

  echo ""
  echo "=== Alpaca (required for now) ==="
  read -r -p "ALPACA_API_KEY: " ALPACA_API_KEY
  read -r -s -p "ALPACA_SECRET_KEY (hidden): " ALPACA_SECRET_KEY
  echo ""

  # defaults
  ALPACA_TRADING_BASE_URL_DEFAULT="https://paper-api.alpaca.markets"
  ALPACA_DATA_BASE_URL_DEFAULT="https://data.alpaca.markets"
  ALPACA_DATA_FEED_DEFAULT="iex"

  echo ""
  read -r -p "ALPACA_TRADING_BASE_URL [${ALPACA_TRADING_BASE_URL_DEFAULT}]: " ALPACA_TRADING_BASE_URL || true
  read -r -p "ALPACA_DATA_BASE_URL [${ALPACA_DATA_BASE_URL_DEFAULT}]: " ALPACA_DATA_BASE_URL || true
  read -r -p "ALPACA_DATA_FEED [${ALPACA_DATA_FEED_DEFAULT}]: " ALPACA_DATA_FEED || true

  ALPACA_TRADING_BASE_URL="${ALPACA_TRADING_BASE_URL:-$ALPACA_TRADING_BASE_URL_DEFAULT}"
  ALPACA_DATA_BASE_URL="${ALPACA_DATA_BASE_URL:-$ALPACA_DATA_BASE_URL_DEFAULT}"
  ALPACA_DATA_FEED="${ALPACA_DATA_FEED:-$ALPACA_DATA_FEED_DEFAULT}"

  # safety defaults
  EXECUTION_MODE_DEFAULT="dry_run"

  echo ""
  read -r -p "EXECUTION_MODE [${EXECUTION_MODE_DEFAULT}] (dry_run/live): " EXECUTION_MODE || true
  EXECUTION_MODE="${EXECUTION_MODE:-$EXECUTION_MODE_DEFAULT}"

  cat > "${ENV_FILE}" <<ENV
# ===== Firebase =====
FIREBASE_DATABASE_URL=${FIREBASE_DATABASE_URL}
FIREBASE_WEB_API_KEY=${FIREBASE_WEB_API_KEY}

# ===== Bot =====
EXECUTION_MODE=${EXECUTION_MODE}

# ===== Alpaca =====
ALPACA_API_KEY=${ALPACA_API_KEY}
ALPACA_SECRET_KEY=${ALPACA_SECRET_KEY}
ALPACA_TRADING_BASE_URL=${ALPACA_TRADING_BASE_URL}
ALPACA_DATA_BASE_URL=${ALPACA_DATA_BASE_URL}
ALPACA_DATA_FEED=${ALPACA_DATA_FEED}
ENV

  chmod 600 "${ENV_FILE}"
  echo "[OK] bot.env created."
}

first_run_pairing() {
  echo ""
  echo "=== First Run Login & Pairing ==="
  echo "You will be asked for email/password, then a pairing code will be shown."
  echo "Approve it from the mobile app."
  echo ""

  cd "${APP_DIR}"
  docker compose pull

  # interactive first run (login + pairing)
  docker compose run --rm thecouncilai-bot

  echo ""
  echo "[OK] Pairing completed."
}

start_services() {
  cd "${APP_DIR}"
  docker compose up -d
  echo "[OK] Bot is running in background."
}

print_commands() {
  echo ""
  echo "=== Useful Commands ==="
  echo "Status:   cd ${APP_DIR} && docker compose ps"
  echo "Logs:     cd ${APP_DIR} && docker compose logs -f --tail=200 thecouncilai-bot"
  echo "Restart:  cd ${APP_DIR} && docker compose restart thecouncilai-bot"
  echo "Stop:     cd ${APP_DIR} && docker compose down"
  echo ""
  echo "Auto-update: Watchtower checks every 5 minutes and updates the bot automatically."
  echo ""
}

main() {
  need_root
  install_docker_if_needed
  install_compose_if_needed
  write_compose
  prompt_env
  first_run_pairing
  start_services
  print_commands
}

main "$@"
