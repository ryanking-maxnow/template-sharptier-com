#!/usr/bin/env bash
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
set -euo pipefail

APP_DIR="/home/template-sharptier-cms"
SHARED_DIR="$APP_DIR/shared"
BACKUP_DIR="$APP_DIR/backups"
TEMP_DIR="/tmp/template-sharptier-restore-$$"

DEPLOY_ENV="$SHARED_DIR/deploy.env"
APP_ENV="$SHARED_DIR/app.env"

DB_HOST="127.0.0.1"
DB_PORT="5432"
DB_USER=""
DB_NAME=""
DB_PASSWORD=""
DATABASE_URI=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

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
    log_error "DB_USER or DB_NAME missing"
    exit 1
  fi
}

check_environment() {
  if [ "${EUID}" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
  fi

  command -v psql >/dev/null 2>&1 || { log_error "psql not found"; exit 1; }
  command -v pg_restore >/dev/null 2>&1 || { log_error "pg_restore not found"; exit 1; }

  if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1" >/dev/null 2>&1; then
    log_error "Cannot connect PostgreSQL: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
    exit 1
  fi
}

list_backups() {
  echo -e "${BLUE}Available backups:${NC}"
  echo ""
  echo "Database backups:"
  find "$BACKUP_DIR/database" -type f \( -name "*.sql.gz" -o -name "*.sql" -o -name "*.dump" \) -printf "  %TY-%Tm-%Td %TH:%TM  %s bytes  %p\n" 2>/dev/null | sort -r | head -20 || echo "  none"
  echo ""
  echo "Archive backups:"
  find "$BACKUP_DIR/archives" -type f -name "*.tar.gz" -printf "  %TY-%Tm-%Td %TH:%TM  %s bytes  %p\n" 2>/dev/null | sort -r | head -20 || echo "  none"
}

confirm_restore() {
  local file="$1"

  echo -e "${RED}WARNING: restore will overwrite current data.${NC}"
  echo "Backup file: $file"
  echo "Target DB: $DB_NAME ($DB_USER@$DB_HOST:$DB_PORT)"
  read -r -p "Type YES to continue: " confirm

  if [ "$confirm" != "YES" ]; then
    log_info "Restore cancelled"
    exit 0
  fi
}

stop_app() {
  if command -v pm2 >/dev/null 2>&1; then
    pm2 stop template-sharptier-cms >/dev/null 2>&1 || true
  fi
}

start_app() {
  if command -v pm2 >/dev/null 2>&1; then
    pm2 start template-sharptier-cms >/dev/null 2>&1 || pm2 restart template-sharptier-cms >/dev/null 2>&1 || true
    pm2 save >/dev/null 2>&1 || true
  fi
}

reset_public_schema() {
  PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public AUTHORIZATION ${DB_USER};
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL ON SCHEMA public TO public;
SQL
}

restore_sql() {
  local file="$1"
  local sql_file="$TEMP_DIR/restore.sql"

  mkdir -p "$TEMP_DIR"

  if [[ "$file" == *.gz ]]; then
    gunzip -c "$file" > "$sql_file"
  else
    cp "$file" "$sql_file"
  fi

  stop_app
  reset_public_schema

  if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$sql_file"; then
    log_success "SQL restore completed"
  else
    log_error "SQL restore failed"
    return 1
  fi

  start_app
}

restore_dump() {
  local file="$1"

  stop_app
  reset_public_schema

  if PGPASSWORD="$DB_PASSWORD" pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" --clean --if-exists "$file"; then
    log_success "Custom dump restore completed"
  else
    log_error "Custom dump restore failed"
    return 1
  fi

  start_app
}

restore_files_from_archive() {
  local file="$1"

  mkdir -p "$TEMP_DIR"
  tar -xzf "$file" -C "$TEMP_DIR"

  if ls "$TEMP_DIR"/*.sql.gz >/dev/null 2>&1; then
    local latest_sql
    latest_sql=$(ls -t "$TEMP_DIR"/*.sql.gz | head -1)
    restore_sql "$latest_sql"
  elif ls "$TEMP_DIR"/*.sql >/dev/null 2>&1; then
    local latest_sql_plain
    latest_sql_plain=$(ls -t "$TEMP_DIR"/*.sql | head -1)
    restore_sql "$latest_sql_plain"
  elif ls "$TEMP_DIR"/*.dump >/dev/null 2>&1; then
    local latest_dump
    latest_dump=$(ls -t "$TEMP_DIR"/*.dump | head -1)
    restore_dump "$latest_dump"
  else
    log_warn "No database file found in archive"
  fi

  if [ -f "$TEMP_DIR/etc/nginx/sites-available/template-sharptier-cms.conf" ]; then
    cp "$TEMP_DIR/etc/nginx/sites-available/template-sharptier-cms.conf" /etc/nginx/sites-available/template-sharptier-cms.conf
    log_success "Restored nginx site config"
  fi

  if [ -f "$TEMP_DIR/etc/nginx/conf.d/acme_issuer.conf" ]; then
    cp "$TEMP_DIR/etc/nginx/conf.d/acme_issuer.conf" /etc/nginx/conf.d/acme_issuer.conf
    log_success "Restored acme issuer config"
  fi

  if [ -f "$TEMP_DIR/home/template-sharptier-cms/shared/app.env" ]; then
    mkdir -p "$SHARED_DIR"
    cp "$TEMP_DIR/home/template-sharptier-cms/shared/app.env" "$SHARED_DIR/app.env"
    chmod 600 "$SHARED_DIR/app.env"
    log_success "Restored shared app.env"
  fi

  if [ -f "$TEMP_DIR/home/template-sharptier-cms/shared/deploy.env" ]; then
    mkdir -p "$SHARED_DIR"
    cp "$TEMP_DIR/home/template-sharptier-cms/shared/deploy.env" "$SHARED_DIR/deploy.env"
    chmod 600 "$SHARED_DIR/deploy.env"
    log_success "Restored shared deploy.env"
  fi

  if command -v nginx >/dev/null 2>&1; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi
}

main() {
  local backup_file="${1:-}"

  load_env
  check_environment

  if [ -z "$backup_file" ]; then
    list_backups
    exit 0
  fi

  if [ ! -f "$backup_file" ]; then
    log_error "Backup file not found: $backup_file"
    exit 1
  fi

  confirm_restore "$backup_file"

  case "$backup_file" in
    *.sql|*.sql.gz)
      restore_sql "$backup_file"
      ;;
    *.dump)
      restore_dump "$backup_file"
      ;;
    *.tar.gz)
      restore_files_from_archive "$backup_file"
      ;;
    *)
      log_error "Unsupported backup format"
      exit 1
      ;;
  esac

  log_success "Restore completed"
}

main "$@"
