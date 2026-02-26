#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/template-sharptier-cms"
SHARED_DIR="$APP_DIR/shared"
BACKUP_DIR="$APP_DIR/backups"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d_%H%M%S)

DEPLOY_ENV="$SHARED_DIR/deploy.env"
APP_ENV="$SHARED_DIR/app.env"

DB_HOST="127.0.0.1"
DB_PORT="5432"
DB_USER=""
DB_NAME=""
DB_PASSWORD=""
DATABASE_URI=""

BACKUP_DB=true
BACKUP_FILES=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

show_help() {
  cat <<HELP
template-sharptier-cms backup script

Usage:
  $0 [options]

Options:
  --db-only      backup database only
  --files-only   backup files/config only
  --help         show help
HELP
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --db-only)
        BACKUP_FILES=false
        ;;
      --files-only)
        BACKUP_DB=false
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
    shift
  done
}

load_env() {
  if [ -f "$DEPLOY_ENV" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$DEPLOY_ENV"
    set +a
  fi

  if [ -f "$APP_ENV" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$APP_ENV"
    set +a
  fi

  DB_HOST="${DB_HOST:-${PGHOST:-127.0.0.1}}"
  DB_PORT="${DB_PORT:-${PGPORT:-5432}}"
  DB_USER="${DB_USER:-}"
  DB_NAME="${DB_NAME:-}"
  DB_PASSWORD="${DB_PASSWORD:-}"
  DATABASE_URI="${DATABASE_URI:-}"

  if [ -n "$DATABASE_URI" ]; then
    local parsed
    parsed=$(echo "$DATABASE_URI" | sed -nE 's#^postgres(ql)?://([^:]+):([^@]+)@([^:/]+):?([0-9]+)?/([^?]+).*$#\2|\3|\4|\5|\6#p')
    if [ -n "$parsed" ]; then
      IFS='|' read -r uri_user uri_pass uri_host uri_port uri_db <<< "$parsed"
      DB_USER="${DB_USER:-$uri_user}"
      DB_PASSWORD="${DB_PASSWORD:-$uri_pass}"
      DB_HOST="${DB_HOST:-$uri_host}"
      DB_PORT="${DB_PORT:-${uri_port:-5432}}"
      DB_NAME="${DB_NAME:-$uri_db}"
    fi
  fi

  if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
    log_error "DB_USER or DB_NAME is empty. Check $DEPLOY_ENV / $APP_ENV"
    exit 1
  fi
}

check_environment() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
  fi

  command -v pg_dump >/dev/null 2>&1 || { log_error "pg_dump not found"; exit 1; }
  command -v psql >/dev/null 2>&1 || { log_error "psql not found"; exit 1; }

  mkdir -p "$BACKUP_DIR/database" "$BACKUP_DIR/files" "$BACKUP_DIR/archives"

  if [ "$BACKUP_DB" = true ]; then
    if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1" >/dev/null 2>&1; then
      log_error "Cannot connect PostgreSQL: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
      exit 1
    fi
  fi
}

backup_database() {
  if [ "$BACKUP_DB" = false ]; then
    return
  fi

  log_info "Backing up database..."

  local sql_file="$BACKUP_DIR/database/${DB_NAME}_${DATE}.sql"
  local sql_gz="$sql_file.gz"
  local dump_file="$BACKUP_DIR/database/${DB_NAME}_${DATE}.dump"

  if PGPASSWORD="$DB_PASSWORD" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > "$sql_file"; then
    gzip "$sql_file"
    log_success "SQL backup done: $sql_gz"
  else
    log_error "SQL backup failed"
    return 1
  fi

  if PGPASSWORD="$DB_PASSWORD" pg_dump -Fc -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > "$dump_file"; then
    log_success "Custom backup done: $dump_file"
  else
    log_warn "Custom backup failed"
  fi
}

backup_files() {
  if [ "$BACKUP_FILES" = false ]; then
    return
  fi

  log_info "Backing up files/config..."

  local files_backup="$BACKUP_DIR/files/template-sharptier-cms-files_${DATE}.tar.gz"
  local items=()

  [ -f "$SHARED_DIR/deploy.env" ] && items+=("$SHARED_DIR/deploy.env")
  [ -f "$SHARED_DIR/app.env" ] && items+=("$SHARED_DIR/app.env")
  [ -f "/etc/nginx/sites-available/template-sharptier-cms.conf" ] && items+=("/etc/nginx/sites-available/template-sharptier-cms.conf")
  [ -f "/etc/nginx/conf.d/acme_issuer.conf" ] && items+=("/etc/nginx/conf.d/acme_issuer.conf")

  if [ ${#items[@]} -eq 0 ]; then
    log_warn "No files to backup"
    return
  fi

  tar -czf "$files_backup" "${items[@]}"
  log_success "Files backup done: $files_backup"
}

create_archive() {
  local archive_file="$BACKUP_DIR/archives/template-sharptier-cms-full_${DATE}.tar.gz"
  local temp_dir="$BACKUP_DIR/.archive_temp_${DATE}"

  mkdir -p "$temp_dir"

  find "$BACKUP_DIR/database" -maxdepth 1 -type f -name "*_${DATE}*" -exec cp {} "$temp_dir" \; 2>/dev/null || true
  find "$BACKUP_DIR/files" -maxdepth 1 -type f -name "*_${DATE}*" -exec cp {} "$temp_dir" \; 2>/dev/null || true

  if [ "$(find "$temp_dir" -maxdepth 1 -type f | wc -l)" -gt 0 ]; then
    tar -czf "$archive_file" -C "$temp_dir" .
    log_success "Archive backup done: $archive_file"
  fi

  rm -rf "$temp_dir"
}

cleanup_old() {
  find "$BACKUP_DIR/database" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
  find "$BACKUP_DIR/files" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
  find "$BACKUP_DIR/archives" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
}

main() {
  parse_args "$@"
  load_env
  check_environment

  backup_database
  backup_files
  create_archive
  cleanup_old

  log_success "Backup completed"
}

main "$@"
