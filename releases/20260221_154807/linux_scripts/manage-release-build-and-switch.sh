#!/usr/bin/env bash
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
set -euo pipefail

START_TS=$(date +%s)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

BASE_DIR="/home/template-sharptier-cms"
RELEASES_DIR="$BASE_DIR/releases"
CURRENT_LINK="$BASE_DIR/current"
SHARED_DIR="$BASE_DIR/shared"
APP_ENV_FILE="$SHARED_DIR/app.env"
DEPLOY_ENV_FILE="$SHARED_DIR/deploy.env"
PM2_APP_NAME="template-sharptier-cms"
PM2_ECOSYSTEM="$BASE_DIR/ecosystem.config.cjs"
NODE_MEM_SCRIPT="$BASE_DIR/scripts/calc-node-mem.mjs"
DB_MIGRATE_SCRIPT="$BASE_DIR/scripts/db-migrate.sh"
KEEP_RELEASES=3

SWITCH=true
RELOAD=true
RUN_MIGRATIONS=false

RELEASE_DIR=""
NODE_MEM_LIMIT_MB=""
APP_PORT="3001"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

usage() {
  cat <<USAGE
Usage: $0 [--no-switch] [--no-reload] [--run-migrations] [--keep N]

Options:
  --no-switch       build only, do not switch current symlink
  --no-reload       switch symlink but skip PM2 / Nginx reload
  --run-migrations  run payload migrations before build
  --keep N          keep latest N releases (default: 3)
  -h, --help        show help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-switch)
      SWITCH=false
      ;;
    --no-reload)
      RELOAD=false
      ;;
    --run-migrations)
      RUN_MIGRATIONS=true
      ;;
    --keep)
      shift
      KEEP_RELEASES="${1:-}"
      if ! [[ "$KEEP_RELEASES" =~ ^[0-9]+$ ]] || [ "$KEEP_RELEASES" -le 0 ]; then
        log_error "--keep requires integer > 0"
        exit 1
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Missing command: $1"
    exit 1
  fi
}

ensure_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
  fi
}

ensure_node() {
  local node_major
  node_major=$(node -v | sed -E 's/^v([0-9]+).*/\1/')
  if [ "$node_major" -lt 24 ]; then
    log_error "Node.js >= 24 required (current: $(node -v))"
    exit 1
  fi
}

load_env() {
  if [ ! -f "$APP_ENV_FILE" ]; then
    log_error "Missing app env: $APP_ENV_FILE"
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$APP_ENV_FILE"
  if [ -f "$DEPLOY_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$DEPLOY_ENV_FILE"
  fi
  set +a

  if [ -z "${DATABASE_URI:-}" ] || [ -z "${PAYLOAD_SECRET:-}" ]; then
    log_error "DATABASE_URI or PAYLOAD_SECRET missing in env"
    exit 1
  fi

  APP_PORT="${APP_PORT:-3001}"
  if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
    log_error "APP_PORT must be numeric, got: $APP_PORT"
    exit 1
  fi
}

calc_node_mem() {
  local value="4096"

  if [ -f "$NODE_MEM_SCRIPT" ]; then
    value=$(node "$NODE_MEM_SCRIPT" 2>/dev/null || echo "4096")
  fi

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    value="4096"
  fi

  if [ "$value" -lt 1000 ]; then
    value="1000"
  fi

  echo "$value"
}

prepare_release_dir() {
  local release_id
  release_id=$(date +%Y%m%d_%H%M%S)

  mkdir -p "$RELEASES_DIR"
  RELEASE_DIR="$RELEASES_DIR/$release_id"
  mkdir -p "$RELEASE_DIR"

  log_info "Creating release: $RELEASE_DIR"

  rsync -a --delete \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --exclude='.next/' \
    --exclude='releases/' \
    --exclude='current' \
    --exclude='backups/' \
    --exclude='logs/' \
    --exclude='shared/' \
    --exclude='.env' \
    --exclude='app.env' \
    --exclude='deploy.env' \
    "$BASE_DIR/" "$RELEASE_DIR/"

  cp "$APP_ENV_FILE" "$RELEASE_DIR/.env"
  chmod 600 "$RELEASE_DIR/.env"
}

build_release() {
  local build_opts
  NODE_MEM_LIMIT_MB=$(calc_node_mem)
  build_opts="--no-deprecation --max-old-space-size=${NODE_MEM_LIMIT_MB}"

  log_info "Node build memory: ${NODE_MEM_LIMIT_MB}MB"

  cd "$RELEASE_DIR"

  NODE_OPTIONS="$build_opts" pnpm install --frozen-lockfile

  if [ "$RUN_MIGRATIONS" = true ]; then
    if [ ! -x "$DB_MIGRATE_SCRIPT" ]; then
      log_error "Missing db migrate script: $DB_MIGRATE_SCRIPT"
      exit 1
    fi
    log_info "Running database migrations via manual script"
    "$DB_MIGRATE_SCRIPT"
  fi

  log_info "Running production build"
  NODE_OPTIONS="$build_opts" pnpm build
}

switch_release() {
  if [ "$SWITCH" = false ]; then
    log_warn "Skip switch (--no-switch)"
    return
  fi

  ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"
  log_success "Switched current -> $RELEASE_DIR"
}

reload_services() {
  if [ "$RELOAD" = false ]; then
    log_warn "Skip reload (--no-reload)"
    return
  fi

  if [ ! -f "$PM2_ECOSYSTEM" ]; then
    log_error "Missing PM2 ecosystem file: $PM2_ECOSYSTEM"
    exit 1
  fi

  pm2 startOrReload "$PM2_ECOSYSTEM" --update-env || pm2 start "$PM2_ECOSYSTEM"
  pm2 save >/dev/null 2>&1 || true

  if command -v nginx >/dev/null 2>&1; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi

  log_success "PM2 reload complete"
}

verify_release() {
  local health_url="http://127.0.0.1:${APP_PORT}/api/health"

  log_info "Checking health: $health_url"
  if ! curl -fsS --max-time 8 "$health_url" >/dev/null; then
    log_error "Health check failed"
    return 1
  fi

  log_success "Health check passed"
}

cleanup_old_releases() {
  mapfile -t all_releases < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%p\n' | sort)
  local total="${#all_releases[@]}"

  if [ "$total" -le "$KEEP_RELEASES" ]; then
    return
  fi

  local remove_count=$((total - KEEP_RELEASES))
  local i=0
  while [ "$i" -lt "$remove_count" ]; do
    local target="${all_releases[$i]}"
    if [ "$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)" = "$target" ]; then
      i=$((i + 1))
      continue
    fi
    rm -rf "$target"
    log_info "Removed old release: $target"
    i=$((i + 1))
  done
}

show_summary() {
  local end_ts elapsed
  end_ts=$(date +%s)
  elapsed=$((end_ts - START_TS))

  echo
  echo -e "${BLUE}==================== RELEASE SUMMARY ====================${NC}"
  echo "  - Start Time:  $START_HUMAN"
  echo "  - End Time:    $(date '+%Y-%m-%d %H:%M:%S')"
  echo "  - Duration:    ${elapsed}s"
  echo "  - Release Dir: $RELEASE_DIR"
  echo "  - Node Memory: ${NODE_MEM_LIMIT_MB}MB"
  echo "  - Current Link: $(readlink -f "$CURRENT_LINK" 2>/dev/null || echo 'N/A')"
  echo -e "${BLUE}=========================================================${NC}"
}

main() {
  ensure_root
  require_cmd node
  require_cmd pnpm
  require_cmd pm2
  require_cmd rsync
  require_cmd curl
  ensure_node

  load_env
  prepare_release_dir
  build_release
  switch_release
  reload_services
  verify_release
  cleanup_old_releases
  show_summary

  log_success "Release pipeline completed"
}

main "$@"
