#!/usr/bin/env bash
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
set -euo pipefail

BASE_DIR="/home/sharptier-cms"
PAYLOAD_DIR="$BASE_DIR/payloadcms"
ASTRO_DIR="$BASE_DIR/astro-frontend"
RELEASE_SCRIPT="$BASE_DIR/linux_scripts/manage-release-build-and-switch.sh"
ASTRO_ENV_SCRIPT="$BASE_DIR/scripts/generate-astro-env.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

check_env() {
  for d in "$BASE_DIR" "$PAYLOAD_DIR" "$ASTRO_DIR"; do
    if [ ! -d "$d" ]; then
      log_error "Missing directory: $d"
      exit 1
    fi
  done

  if ! command -v pnpm >/dev/null 2>&1; then
    if command -v corepack >/dev/null 2>&1; then
      corepack enable pnpm >/dev/null 2>&1 || true
    fi
  fi

  if ! command -v pnpm >/dev/null 2>&1; then
    log_error "pnpm is not installed"
    exit 1
  fi
}

calc_node_mem() {
  local script="$BASE_DIR/scripts/calc-node-mem.mjs"
  if [ -f "$script" ]; then
    node "$script"
  else
    echo "4096"
  fi
}

show_header() {
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════════╗"
  echo "║     sharptier-cms PNPM 工具箱                 ║"
  echo "╚════════════════════════════════════════════╝"
  echo -e "${NC}"
}

show_menu() {
  show_header
  cat <<MENU
1) payload dev               - pnpm --dir payloadcms dev
2) payload build             - pnpm --dir payloadcms build
3) payload generate:types    - pnpm --dir payloadcms generate:types
4) astro dev                 - pnpm --dir astro-frontend dev
5) astro build               - pnpm --dir astro-frontend build
6) astro preview             - pnpm --dir astro-frontend preview
7) release build+switch      - linux_scripts/manage-release-build-and-switch.sh
8) astro env generate        - scripts/generate-astro-env.sh
9) pm2 logs                  - pm2 logs sharptier-cms
10) install all dependencies - pnpm install for payload + astro
0) exit
MENU
  echo
}

run_cmd() {
  local title="$1"
  local cmd="$2"

  echo -e "${CYAN}>>> ${title}${NC}"
  echo -e "${CYAN}${cmd}${NC}"
  eval "$cmd"
  echo -e "${GREEN}>>> done${NC}"
}

do_action() {
  case "$1" in
    1|payload-dev)
      run_cmd "Payload dev" "pnpm --dir '$PAYLOAD_DIR' dev"
      ;;
    2|payload-build)
      export NODE_OPTIONS="--no-deprecation --max-old-space-size=$(calc_node_mem)"
      run_cmd "Payload build" "pnpm --dir '$PAYLOAD_DIR' build"
      ;;
    3|payload-types)
      run_cmd "Payload generate types" "pnpm --dir '$PAYLOAD_DIR' generate:types"
      ;;
    4|astro-dev)
      run_cmd "Astro dev" "pnpm --dir '$ASTRO_DIR' dev"
      ;;
    5|astro-build)
      export NODE_OPTIONS="--no-deprecation --max-old-space-size=$(calc_node_mem)"
      run_cmd "Astro build" "pnpm --dir '$ASTRO_DIR' build"
      ;;
    6|astro-preview)
      run_cmd "Astro preview" "pnpm --dir '$ASTRO_DIR' preview"
      ;;
    7|release)
      if [ ! -x "$RELEASE_SCRIPT" ]; then
        log_error "Missing executable: $RELEASE_SCRIPT"
        exit 1
      fi
      run_cmd "Release build+switch" "$RELEASE_SCRIPT"
      ;;
    8|astro-env)
      if [ ! -x "$ASTRO_ENV_SCRIPT" ]; then
        log_error "Missing executable: $ASTRO_ENV_SCRIPT"
        exit 1
      fi
      run_cmd "Generate Astro env" "$ASTRO_ENV_SCRIPT"
      ;;
    9|logs)
      run_cmd "PM2 logs" "pm2 logs sharptier-cms"
      ;;
    10|install)
      run_cmd "Install payload dependencies" "pnpm --dir '$PAYLOAD_DIR' install --frozen-lockfile"
      run_cmd "Install astro dependencies" "pnpm --dir '$ASTRO_DIR' install --frozen-lockfile"
      ;;
    0|q|quit|exit)
      exit 0
      ;;
    *)
      log_warn "Unknown option: $1"
      return 1
      ;;
  esac
}

main() {
  check_env

  if [ $# -gt 0 ]; then
    do_action "$1"
    exit 0
  fi

  while true; do
    show_menu
    read -r -p "Select an option: " choice
    do_action "$choice" || true
    echo
    read -r -p "Press Enter to continue..." _unused
    echo
  done
}

main "$@"
