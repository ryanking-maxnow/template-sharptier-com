#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/home/template-sharptier-cms"
MIGRATIONS_DIR="$BASE_DIR/database/migrations"
NAME="${1:-}"

if [ -z "$NAME" ]; then
  echo "Usage: $0 <migration-name>" >&2
  exit 1
fi

slug=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
if [ -z "$slug" ]; then
  echo "[ERROR] invalid migration name" >&2
  exit 1
fi

mkdir -p "$MIGRATIONS_DIR"
filename="$(date +%Y%m%d_%H%M%S)_${slug}.sql"
filepath="$MIGRATIONS_DIR/$filename"

cat > "$filepath" <<SQL
-- migration: $filename
-- write idempotent SQL below

-- Example:
-- ALTER TABLE some_table ADD COLUMN IF NOT EXISTS some_column TEXT;
SQL

echo "[SUCCESS] created migration: $filepath"
