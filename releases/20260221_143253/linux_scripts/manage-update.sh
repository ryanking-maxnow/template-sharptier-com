#!/usr/bin/env bash
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
set -euo pipefail

APP_DIR="/home/template-sharptier-cms"
RELEASE_SCRIPT="$APP_DIR/linux_scripts/manage-release-build-and-switch.sh"
BACKUP_SCRIPT="$APP_DIR/linux_scripts/manage-backup.sh"
CURRENT_LINK="$APP_DIR/current"
TARGET_REF=""
FORCE_ROLLBACK=false
PREVIOUS_CURRENT=""
ROLLBACK_TAG=""

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
Usage: $0 [git-ref] [--rollback]

Examples:
  $0
  $0 main
  $0 v1.2.3
  $0 --rollback
USAGE
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --rollback)
        FORCE_ROLLBACK=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [ -n "$TARGET_REF" ]; then
          log_error "Only one git ref is supported"
          exit 1
        fi
        TARGET_REF="$1"
        ;;
    esac
    shift
  done
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Missing command: $1"
    exit 1
  fi
}

check_env() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
  fi

  require_cmd git
  require_cmd curl

  if [ ! -d "$APP_DIR/.git" ]; then
    log_error "Not a git repository: $APP_DIR"
    exit 1
  fi

  if [ ! -x "$RELEASE_SCRIPT" ]; then
    log_error "Release script missing: $RELEASE_SCRIPT"
    exit 1
  fi
}

capture_current() {
  PREVIOUS_CURRENT=$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)
}

create_backup() {
  if [ -x "$BACKUP_SCRIPT" ]; then
    log_info "Creating pre-update database backup"
    "$BACKUP_SCRIPT" --db-only || log_warn "Backup failed, continue"
  else
    log_warn "Backup script missing, skip"
  fi
}

prepare_git() {
  cd "$APP_DIR"

  ROLLBACK_TAG="pre-update-$(date +%Y%m%d_%H%M%S)"
  git tag "$ROLLBACK_TAG"

  if ! git diff-index --quiet HEAD --; then
    log_warn "Local changes detected, auto stash"
    git stash push -u -m "auto stash before update $(date +%Y-%m-%d_%H:%M:%S)" >/dev/null
  fi

  git fetch --all --tags

  if [ -n "$TARGET_REF" ]; then
    log_info "Checking out target ref: $TARGET_REF"
    git checkout "$TARGET_REF"
  else
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    log_info "Pulling latest for branch: $branch"
    git pull --ff-only origin "$branch"
  fi
}

reload_runtime() {
  if command -v pm2 >/dev/null 2>&1; then
    pm2 reload template-sharptier-cms --update-env >/dev/null 2>&1 || true
  fi

  if command -v nginx >/dev/null 2>&1; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi
}

verify() {
  if ! curl -fsS "http://127.0.0.1:3000/api/health" >/dev/null; then
    log_error "Health check failed"
    return 1
  fi
  log_success "Health check passed"
}

rollback_current() {
  if [ -z "$PREVIOUS_CURRENT" ] || [ ! -d "$PREVIOUS_CURRENT" ]; then
    log_error "No previous release recorded"
    return 1
  fi

  ln -sfn "$PREVIOUS_CURRENT" "$CURRENT_LINK"
  reload_runtime
}

rollback_previous_release() {
  mapfile -t releases < <(find "$APP_DIR/releases" -mindepth 1 -maxdepth 1 -type d -printf '%p\n' | sort)

  if [ "${#releases[@]}" -lt 2 ]; then
    log_error "Not enough releases for rollback"
    exit 1
  fi

  local target="${releases[$((${#releases[@]} - 2))]}"
  ln -sfn "$target" "$CURRENT_LINK"
  reload_runtime

  if verify; then
    log_success "Rollback completed"
  else
    log_error "Rollback verification failed"
    exit 1
  fi
}

main() {
  parse_args "$@"
  check_env

  if [ "$FORCE_ROLLBACK" = true ]; then
    rollback_previous_release
    exit 0
  fi

  capture_current
  create_backup
  prepare_git

  if ! "$RELEASE_SCRIPT" --run-migrations; then
    log_error "Release failed, rolling back"
    rollback_current || true
    exit 1
  fi

  if verify; then
    log_success "Update completed"
    echo "Rollback tag: $ROLLBACK_TAG"
    exit 0
  fi

  log_error "Post-deploy verification failed, rollback started"
  rollback_current || true

  if verify; then
    log_success "Rollback succeeded"
  else
    log_error "Rollback failed, manual intervention required"
    exit 1
  fi
}

main "$@"
