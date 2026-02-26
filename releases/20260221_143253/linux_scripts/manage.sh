#!/usr/bin/env bash
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
set -euo pipefail

APP_DIR="/home/template-sharptier-cms"
PM2_ECOSYSTEM="$APP_DIR/ecosystem.config.cjs"
BACKUP_SCRIPT="$APP_DIR/linux_scripts/manage-backup.sh"
RESTORE_SCRIPT="$APP_DIR/linux_scripts/manage-restore.sh"
UPDATE_SCRIPT="$APP_DIR/linux_scripts/manage-update.sh"
RELEASE_SCRIPT="$APP_DIR/linux_scripts/manage-release-build-and-switch.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
  cat <<EOF_HELP
Template SharpTier CMS manage tool

Usage:
  $0 <command> [args]

Commands:
  status                 show runtime status
  start                  start app via PM2
  stop                   stop app via PM2
  restart                restart app via PM2
  logs                   tail app logs via PM2
  build-release          run release build and switch
  backup [opts]          run backup script
  restore <file>         run restore script
  update [git-ref]       run update script
  nginx <op>             nginx test|reload|restart|status
  help                   show this help
EOF_HELP
}

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
  fi
}

status() {
  echo -e "${BLUE}========== Template SharpTier CMS Status ==========${NC}"
  echo -e "${CYAN}PM2:${NC}"
  if command -v pm2 >/dev/null 2>&1; then
    pm2 status template-sharptier-cms || true
  else
    echo "pm2 not found"
  fi

  echo
  echo -e "${CYAN}Nginx:${NC}"
  if command -v nginx >/dev/null 2>&1; then
    systemctl is-active nginx || true
    nginx -v 2>&1 || true
  else
    echo "nginx not found"
  fi

  echo
  echo -e "${CYAN}PostgreSQL:${NC}"
  if command -v psql >/dev/null 2>&1; then
    systemctl is-active postgresql || true
    psql --version || true
  else
    echo "psql not found"
  fi

  echo
  echo -e "${CYAN}Current release:${NC}"
  readlink -f "$APP_DIR/current" || echo "not set"
}

start_app() {
  require_root
  if [ ! -f "$PM2_ECOSYSTEM" ]; then
    log_error "Missing ecosystem file: $PM2_ECOSYSTEM"
    exit 1
  fi
  pm2 startOrReload "$PM2_ECOSYSTEM" --update-env || pm2 start "$PM2_ECOSYSTEM"
  pm2 save >/dev/null 2>&1 || true
}

stop_app() {
  require_root
  pm2 stop template-sharptier-cms || true
}

restart_app() {
  require_root
  pm2 restart template-sharptier-cms --update-env || start_app
  pm2 save >/dev/null 2>&1 || true
}

nginx_op() {
  require_root
  local op="${1:-}"
  case "$op" in
    test)
      nginx -t
      ;;
    reload)
      nginx -t && systemctl reload nginx
      ;;
    restart)
      systemctl restart nginx
      ;;
    status)
      systemctl status nginx --no-pager
      ;;
    *)
      log_error "Usage: $0 nginx <test|reload|restart|status>"
      exit 1
      ;;
  esac
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    status)
      status
      ;;
    start)
      start_app
      ;;
    stop)
      stop_app
      ;;
    restart)
      restart_app
      ;;
    logs)
      pm2 logs template-sharptier-cms
      ;;
    build-release)
      require_root
      "$RELEASE_SCRIPT" "$@"
      ;;
    backup)
      require_root
      "$BACKUP_SCRIPT" "$@"
      ;;
    restore)
      require_root
      "$RESTORE_SCRIPT" "$@"
      ;;
    update)
      require_root
      "$UPDATE_SCRIPT" "$@"
      ;;
    nginx)
      nginx_op "$@"
      ;;
    help|-h|--help)
      show_help
      ;;
    *)
      log_error "Unknown command: $cmd"
      show_help
      exit 1
      ;;
  esac
}

main "$@"
