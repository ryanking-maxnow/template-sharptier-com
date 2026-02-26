#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/home/template-sharptier-cms"
APP_ENV="$BASE_DIR/shared/app.env"
MIGRATIONS_DIR="$BASE_DIR/database/migrations"

if [ ! -d "$MIGRATIONS_DIR" ]; then
  echo "[ERROR] migrations directory not found: $MIGRATIONS_DIR" >&2
  exit 1
fi

if [ -f "$APP_ENV" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$APP_ENV"
  set +a
fi

DATABASE_URI="${DATABASE_URI:-${DATABASE_URL:-}}"

if [ -z "$DATABASE_URI" ]; then
  echo "[ERROR] DATABASE_URI or DATABASE_URL is required" >&2
  exit 1
fi

parsed=$(echo "$DATABASE_URI" | sed -nE 's#^postgres(ql)?://([^:]+):([^@]+)@([^:/]+):?([0-9]+)?/([^?]+).*$#\2|\3|\4|\5|\6#p')
if [ -z "$parsed" ]; then
  echo "[ERROR] failed to parse DATABASE_URI" >&2
  exit 1
fi

IFS='|' read -r DB_USER DB_PASSWORD DB_HOST DB_PORT DB_NAME <<< "$parsed"
DB_PORT="${DB_PORT:-5432}"

PSQL=(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1)

export PGPASSWORD="$DB_PASSWORD"

"${PSQL[@]}" <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  filename TEXT PRIMARY KEY,
  checksum TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
SQL

apply_sql_migration() {
  local file="$1"
  local filename checksum existing

  filename=$(basename "$file")
  checksum=$(sha256sum "$file" | awk '{print $1}')
  existing=$("${PSQL[@]}" -tAc "SELECT checksum FROM schema_migrations WHERE filename = '$filename';" | xargs || true)

  if [ -n "$existing" ]; then
    if [ "$existing" != "$checksum" ]; then
      echo "[ERROR] checksum mismatch for applied migration: $filename" >&2
      exit 1
    fi
    echo "[INFO] skip already applied migration: $filename"
    return
  fi

  echo "[INFO] applying migration: $filename"
  "${PSQL[@]}" -f "$file"
  "${PSQL[@]}" -c "INSERT INTO schema_migrations (filename, checksum) VALUES ('$filename', '$checksum');"
}

while IFS= read -r file; do
  apply_sql_migration "$file"
done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' | sort)

if [ -d "$BASE_DIR/src/migrations" ]; then
  echo "[INFO] running payload migrations (non-interactive)"
  cd "$BASE_DIR"
  pnpm payload migrate
fi

echo "[SUCCESS] db migrations completed"
