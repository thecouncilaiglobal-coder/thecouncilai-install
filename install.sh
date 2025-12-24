#!/usr/bin/env bash
set -euo pipefail

# ---- TheCouncilAI Bot Installer (Linux / Ubuntu-Debian) ----
# Goal: single-command install; only asks for app email/password + pairing approval.
# Broker API keys are provisioned later from the mobile app via encrypted command channel.

BOT_DIR="${BOT_DIR:-/opt/thecouncilai/bot}"
IMAGE="${IMAGE:-ghcr.io/thecouncilaiglobal-coder/thecouncilai-bot:stable}"
WATCHTOWER_INTERVAL="${WATCHTOWER_INTERVAL:-300}"

# Firebase (required) - these are not secrets
DEFAULT_FIREBASE_DATABASE_URL="https://thecouncilai-59a0f-default-rtdb.firebaseio.com"
DEFAULT_FIREBASE_WEB_API_KEY="AIzaSyAuU8cfN4dWJepDfMYYVGufs5ANGxQOq5I"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
  fi
}

detect_docker_repo() {
  if [ ! -f /etc/os-release ]; then
    echo "Unsupported OS: missing /etc/os-release"
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  # Prefer ubuntu if ID_LIKE includes it; otherwise handle debian.
  if echo "${ID_LIKE:-}" | grep -qi "ubuntu" || [ "${ID:-}" = "ubuntu" ]; then
    DOCKER_DISTRO="ubuntu"
    CODENAME="${VERSION_CODENAME:-jammy}"
  elif echo "${ID_LIKE:-}" | grep -qi "debian" || [ "${ID:-}" = "debian" ]; then
    DOCKER_DISTRO="debian"
    CODENAME="${VERSION_CODENAME:-bookworm}"
  else
    echo "Unsupported OS: ${ID:-unknown}. This installer supports Ubuntu/Debian."
    exit 1
  fi

  export DOCKER_DISTRO CODENAME
}

install_docker_if_missing() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return
  fi

  detect_docker_repo

  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DOCKER_DISTRO} ${CODENAME} stable"     > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

write_runtime_files() {
  mkdir -p "$BOT_DIR/data"
  chmod 700 "$BOT_DIR" || true
  chmod 700 "$BOT_DIR/data" || true

  # Create .env only if missing (do not clobber user edits).
  if [ ! -f "$BOT_DIR/.env" ]; then
    cat > "$BOT_DIR/.env" <<EOF
# ===== Firebase Auth (Client-side) =====
FIREBASE_WEB_API_KEY=${FIREBASE_WEB_API_KEY:-$DEFAULT_FIREBASE_WEB_API_KEY}
FIREBASE_DATABASE_URL=${FIREBASE_DATABASE_URL:-$DEFAULT_FIREBASE_DATABASE_URL}

# ===== Signals =====
GLOBAL_SIGNALS_EVENTS_PATH=${GLOBAL_SIGNALS_EVENTS_PATH:-global_council_signal_events}
GLOBAL_SIGNALS_LATEST_PATH=${GLOBAL_SIGNALS_LATEST_PATH:-global_council_signals_latest}

# ===== Local bot storage =====
BOT_DATA_DIR=/data

# ===== Execution =====
EXECUTION_MODE=${EXECUTION_MODE:-paper}   # paper|live|dry_run
LOG_LEVEL=${LOG_LEVEL:-INFO}

# Broker endpoints (non-secret)
ALPACA_TRADING_BASE_URL=${ALPACA_TRADING_BASE_URL:-https://paper-api.alpaca.markets}
ALPACA_DATA_BASE_URL=${ALPACA_DATA_BASE_URL:-https://data.alpaca.markets}
ALPACA_DATA_FEED=${ALPACA_DATA_FEED:-iex}

# Optional: if you still want env-based keys (backward compatible)
# ALPACA_API_KEY=
# ALPACA_SECRET_KEY=

# ===== Command/Telemetry =====
TELEMETRY_WRITE_SECONDS=${TELEMETRY_WRITE_SECONDS:-10}
COMMAND_POLL_SECONDS=${COMMAND_POLL_SECONDS:-5}

# ===== Hygiene (optional; requires bot version that supports pruning) =====
ACKS_KEEP_LAST=${ACKS_KEEP_LAST:-250}
LOGS_KEEP_LAST=${LOGS_KEEP_LAST:-500}
RTDB_PRUNE_INTERVAL_S=${RTDB_PRUNE_INTERVAL_S:-600}
EOF
    chmod 600 "$BOT_DIR/.env"
  else
    echo "Found existing $BOT_DIR/.env - leaving as-is."
  fi

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

  watchtower:
    image: containrrr/watchtower:latest
    container_name: thecouncilai-watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval ${WATCHTOWER_INTERVAL} --cleanup thecouncilai-bot
EOF
}

first_time_setup_interactive() {
  if [ -f "$BOT_DIR/data/.installed" ]; then
    echo "Already initialized (found $BOT_DIR/data/.installed). Skipping interactive first-run."
    return
  fi

  echo ""
  echo "Starting first-time login + pairing..."
  echo "You will be asked for TheCouncilAI app email/password, then pairing approval in the mobile app."
  echo ""

  cd "$BOT_DIR"
  docker compose pull thecouncilai-bot >/dev/null 2>&1 || true
  docker compose run --rm -it thecouncilai-bot

  touch "$BOT_DIR/data/.installed"
}

start_services() {
  cd "$BOT_DIR"
  docker compose up -d --remove-orphans
  echo ""
  echo "Installed."
  echo "Useful commands:"
  echo "  cd $BOT_DIR"
  echo "  docker compose ps"
  echo "  docker logs -f thecouncilai-bot"
  echo "  docker logs -f thecouncilai-watchtower"
}

main() {
  need_root
  install_docker_if_missing
  mkdir -p "$BOT_DIR"
  write_runtime_files
  first_time_setup_interactive
  start_services
}

main "$@"
