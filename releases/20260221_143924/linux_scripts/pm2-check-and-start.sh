#!/usr/bin/env bash
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
set -euo pipefail

BASE_DIR="/home/sharptier-cms"
CURRENT_DIR="$BASE_DIR/current"
ECOSYSTEM_FILE="$BASE_DIR/payloadcms/ecosystem.config.cjs"

if [ ! -L "$CURRENT_DIR" ]; then
  echo "Current release symlink not found: $CURRENT_DIR" >&2
  exit 1
fi

if [ ! -f "$CURRENT_DIR/payloadcms/.next/BUILD_ID" ]; then
  echo "Payload build missing in current release: $CURRENT_DIR/payloadcms/.next/BUILD_ID" >&2
  exit 1
fi

if [ ! -f "$ECOSYSTEM_FILE" ]; then
  echo "PM2 ecosystem file missing: $ECOSYSTEM_FILE" >&2
  exit 1
fi

pm2 startOrReload "$ECOSYSTEM_FILE" --update-env || pm2 start "$ECOSYSTEM_FILE"
pm2 save >/dev/null 2>&1 || true

echo "PM2 started/reloaded for sharptier-cms"
