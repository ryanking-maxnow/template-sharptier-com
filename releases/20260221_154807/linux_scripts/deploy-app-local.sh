#!/usr/bin/env bash
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
set -euo pipefail

BASE_DIR="/home/template-sharptier-cms"
SHARED_DIR="$BASE_DIR/shared"
DEPLOY_ENV="$SHARED_DIR/deploy.env"
APP_ENV="$SHARED_DIR/app.env"
TEMPLATE_FILE="$BASE_DIR/linux_scripts/conf/template-sharptier-cms.conf"
NGINX_SITE="/etc/nginx/sites-available/template-sharptier-cms.conf"
NGINX_LINK="/etc/nginx/sites-enabled/template-sharptier-cms.conf"
ACME_ISSUER_CONF="/etc/nginx/conf.d/acme_issuer.conf"
ACME_ACCOUNT_KEY="/etc/nginx/acme/account.key"
ACME_STATE_PATH="/var/cache/nginx/acme-letsencrypt"
RELEASE_SCRIPT="$BASE_DIR/linux_scripts/manage-release-build-and-switch.sh"

CMS_DOMAIN_ARG="${1:-}"
CMS_DOMAIN=""
ACME_CONTACT_EMAIL=""
APP_PORT=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

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
  require_cmd node
  local node_major
  node_major=$(node -v | sed -E 's/^v([0-9]+).*/\1/')
  if [ "$node_major" -lt 24 ]; then
    log_error "Node.js >= 24 is required (current: $(node -v))"
    exit 1
  fi
}

load_env() {
  if [ ! -f "$DEPLOY_ENV" ] || [ ! -f "$APP_ENV" ]; then
    log_error "Missing env files: $DEPLOY_ENV or $APP_ENV"
    log_info "Copy from /home/template-sharptier-cms/shared/*.example first"
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV"
  # shellcheck disable=SC1090
  source "$APP_ENV"
  set +a

  if [ -n "$CMS_DOMAIN_ARG" ]; then
    CMS_DOMAIN="$CMS_DOMAIN_ARG"
  else
    CMS_DOMAIN="${CMS_DOMAIN:-template.sharptier.com}"
  fi

  if [ -n "${PAYLOAD_ADMIN_EMAIL:-}" ]; then
    ACME_CONTACT_EMAIL="$PAYLOAD_ADMIN_EMAIL"
  else
    ACME_CONTACT_EMAIL="admin@${CMS_DOMAIN#www.}"
  fi

  APP_PORT="${APP_PORT:-3001}"
  if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]]; then
    log_error "APP_PORT must be numeric, got: $APP_PORT"
    exit 1
  fi

  ln -sfn "$DEPLOY_ENV" "$BASE_DIR/deploy.env"
  ln -sfn "$APP_ENV" "$BASE_DIR/.env"
  ln -sfn "$APP_ENV" "$BASE_DIR/app.env"
}

persist_domain() {
  if grep -q '^CMS_DOMAIN=' "$DEPLOY_ENV"; then
    sed -i "s/^CMS_DOMAIN=.*/CMS_DOMAIN=${CMS_DOMAIN}/" "$DEPLOY_ENV"
  else
    echo "CMS_DOMAIN=${CMS_DOMAIN}" >> "$DEPLOY_ENV"
  fi
}

ensure_nginx_layout() {
  mkdir -p /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/snippets /etc/nginx/acme "$ACME_STATE_PATH"

  if [ ! -f /etc/nginx/snippets/proxy_common.conf ]; then
    cat > /etc/nginx/snippets/proxy_common.conf <<'SNIPPET'
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_http_version 1.1;
proxy_read_timeout 60s;
proxy_send_timeout 60s;
SNIPPET
  fi

  if ! grep -q "include /etc/nginx/sites-enabled/\\*\\.conf;" /etc/nginx/nginx.conf 2>/dev/null; then
    log_warn "Nginx config missing sites-enabled include, rewriting /etc/nginx/nginx.conf"
    cat > /etc/nginx/nginx.conf <<'CONF'
user  www-data;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main
        '$remote_addr - $remote_user [$time_local] "$request" '
        '$status $body_bytes_sent "$http_referer" '
        '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    tcp_nopush      on;
    keepalive_timeout  65;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 50m;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*.conf;
}
CONF
  fi
}

ensure_acme_issuer_config() {
  local resolvers

  resolvers=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | paste -sd' ' -)
  if [ -z "$resolvers" ]; then
    resolvers="1.1.1.1 8.8.8.8"
  fi

  if [ ! -f "$ACME_ACCOUNT_KEY" ]; then
    openssl genrsa -out "$ACME_ACCOUNT_KEY" 4096 >/dev/null 2>&1
    chmod 600 "$ACME_ACCOUNT_KEY"
  fi

  chown -R www-data:www-data "$ACME_STATE_PATH"

  cat > "$ACME_ISSUER_CONF" <<CONF
resolver ${resolvers} ipv6=off valid=300s;
resolver_timeout 10s;

acme_issuer letsencrypt {
    uri https://acme-v02.api.letsencrypt.org/directory;
    account_key ${ACME_ACCOUNT_KEY};
    state_path ${ACME_STATE_PATH};
    contact mailto:${ACME_CONTACT_EMAIL};
    accept_terms_of_service;
}

acme_shared_zone zone=ngx_acme_shared:1M;
CONF
}

render_template() {
  local template_path=$1
  local domain=$2
  local upstream=$3
  local upstream_host=$4
  local upstream_name=$5

  awk -v domain="$domain" \
      -v upstream="$upstream" \
      -v upstream_host="$upstream_host" \
      -v upstream_name="$upstream_name" \
      '{
          gsub(/{{DOMAIN}}/, domain)
          gsub(/{{UPSTREAM}}/, upstream)
          gsub(/{{UPSTREAM_HOST}}/, upstream_host)
          gsub(/{{UPSTREAM_NAME}}/, upstream_name)
          print
      }' "$template_path"
}

configure_nginx() {
  require_cmd nginx

  if [ ! -f "$TEMPLATE_FILE" ]; then
    log_error "Nginx template missing: $TEMPLATE_FILE"
    exit 1
  fi

  ensure_nginx_layout
  ensure_acme_issuer_config

  local upstream="http://127.0.0.1:${APP_PORT}"
  local upstream_host="127.0.0.1:${APP_PORT}"
  local upstream_name="template_payload_backend"

  render_template "$TEMPLATE_FILE" "$CMS_DOMAIN" "$upstream" "$upstream_host" "$upstream_name" > "$NGINX_SITE"
  ln -sfn "$NGINX_SITE" "$NGINX_LINK"

  if [ -L /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
  fi

  nginx -t
  systemctl reload nginx || systemctl restart nginx
  log_success "Nginx configured: $NGINX_SITE"
}

deploy_release() {
  if [ ! -x "$RELEASE_SCRIPT" ]; then
    log_error "Missing script: $RELEASE_SCRIPT"
    exit 1
  fi

  log_info "Building and switching release"
  "$RELEASE_SCRIPT" --run-migrations
}

verify_health() {
  log_info "Checking local health endpoint"
  if ! curl -fsS --max-time 5 "http://127.0.0.1:${APP_PORT}/api/health" >/dev/null; then
    log_warn "Local health check failed: /api/health"
    return 1
  fi

  log_info "Checking domain availability"
  if ! curl -fsS --max-time 8 "http://${CMS_DOMAIN}" >/dev/null; then
    log_warn "HTTP domain check failed: http://${CMS_DOMAIN}"
    return 1
  fi

  log_success "Health checks passed"
}

main() {
  ensure_root
  require_cmd curl
  require_cmd sed
  require_cmd awk
  require_cmd openssl
  require_cmd systemctl
  ensure_node

  load_env
  persist_domain
  configure_nginx
  deploy_release
  verify_health || true

  log_success "Deployment completed"
  log_info "Domain: ${CMS_DOMAIN}"
  log_info "Admin: https://${CMS_DOMAIN}/admin"
}

main "$@"
