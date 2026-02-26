#!/bin/bash
#
# sharptier-cms 环境安装脚本
# 安装系统依赖、Docker、Portainer、Nginx
#
# 使用方法:
#   chmod +x setup-environment.sh
#   sudo ./setup-environment.sh [--nginx-version <version>] [--reinstall-nginx]
#
# 功能:
#   - 检查系统环境
#   - 安装系统依赖
#   - 安装 Docker
#   - 编译安装 Nginx (含 ACME、Brotli、VTS 等模块)
#   - 安装 PM2

set -e

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NGINX_VERSION_DEFAULT="1.29.5"
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
SCRIPT_START_TS=$(date +%s)
SCRIPT_START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

SYSTEM_DEP_PACKAGES=(
    curl
    wget
    git
    build-essential
    libpcre3-dev
    libpcre2-dev
    zlib1g-dev
    libssl-dev
    libgd-dev
    libgeoip-dev
    libmaxminddb-dev
    libxslt1-dev
    libxml2-dev
    libperl-dev
    libgoogle-perftools-dev
    libbrotli-dev
    clang
    libclang-dev
    llvm-dev
    ca-certificates
    gnupg
    lsb-release
)

DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
)

# ============================================
# 日志函数
# ============================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

format_duration() {
    local total_seconds="$1"
    local hours minutes seconds
    hours=$((total_seconds / 3600))
    minutes=$(((total_seconds % 3600) / 60))
    seconds=$((total_seconds % 60))
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
}

get_dpkg_version() {
    local pkg="$1"
    dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo "未安装"
}

print_summary_line() {
    local name="$1"
    local version="$2"
    printf "  - %-34s %s\n" "${name}" "${version}"
}

# ============================================
# 检查 root 权限
# ============================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        log_info "使用: sudo ./setup-environment.sh"
        exit 1
    fi
}

# ============================================
# 检查系统
# ============================================
check_system() {
    log_step "检查系统环境"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        log_info "检测到系统: $PRETTY_NAME"
    else
        log_error "无法检测系统版本"
        exit 1
    fi

    case $OS in
        ubuntu)
            if [[ "${VERSION%%.*}" -lt 22 ]]; then
                log_error "需要 Ubuntu 22.04 或更高版本"
                exit 1
            fi
            ;;
        debian)
            if [[ "${VERSION%%.*}" -lt 12 ]]; then
                log_error "需要 Debian 12 或更高版本"
                exit 1
            fi
            ;;
        *)
            log_warn "未测试的系统: $OS，继续安装可能会有问题"
            read -p "是否继续? (y/N): " confirm
            if [[ ! $confirm =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
    esac
}

# ============================================
# 收集配置
# ============================================
collect_config() {
    log_step "配置信息"

    # Nginx 版本 (默认值，可通过参数覆盖)
    NGINX_VERSION=${NGINX_VERSION:-$NGINX_VERSION_DEFAULT}
    log_info "Nginx 版本: $NGINX_VERSION"

    # 保存配置
    mkdir -p /home/sharptier-cms
    cat > /home/sharptier-cms/environment-config.env << EOF
NGINX_VERSION=$NGINX_VERSION
SETUP_DATE=$(date +%Y-%m-%d_%H:%M:%S)
EOF
    chmod 600 /home/sharptier-cms/environment-config.env
    log_info "配置已保存到 /home/sharptier-cms/environment-config.env"
}

# ============================================
# 解析参数
# ============================================
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --nginx-version)
                shift
                NGINX_VERSION="$1"
                ;;
            --nginx-version=*)
                NGINX_VERSION="${1#*=}"
                ;;
            -n)
                shift
                NGINX_VERSION="$1"
                ;;
            --reinstall-nginx)
                NGINX_REINSTALL="1"
                ;;
            -h|--help)
                echo "使用方法:"
                echo "  sudo ./deploy-setup-environment.sh [--nginx-version <version>] [--reinstall-nginx]"
                echo ""
                echo "示例:"
                echo "  sudo ./deploy-setup-environment.sh"
                echo "  sudo ./deploy-setup-environment.sh --nginx-version 1.29.5"
                echo "  sudo ./deploy-setup-environment.sh --reinstall-nginx"
                exit 0
                ;;
        esac
        shift || true
    done
}

# ============================================
# 安装系统依赖
# ============================================
install_dependencies() {
    log_step "安装系统依赖"

    apt update
    apt install -y "${SYSTEM_DEP_PACKAGES[@]}"

    log_info "系统依赖安装完成"
}

# ============================================
# 安装 Docker (官方源)
# ============================================
install_docker() {
    log_step "安装 Docker"

    if command -v docker &> /dev/null; then
        log_info "Docker 已安装: $(docker --version)"
    else
        # 添加 Docker 官方 GPG 密钥
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/${ID}/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # 添加 Docker 官方源 (自动适配 Ubuntu/Debian)
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        # 安装 Docker
        apt update
        apt install -y "${DOCKER_PACKAGES[@]}"
        systemctl enable --now docker
        log_info "Docker 安装完成"
    fi

    # 配置 Docker 日志
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    systemctl restart docker
    log_info "Docker 日志配置完成"
}

# ============================================
# 安装 PM2 (含 Node.js)
# ============================================
install_pm2() {
    log_step "安装 PM2"

    local install_node=0
    if ! command -v node &> /dev/null; then
        install_node=1
    else
        local node_major
        node_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
        if [ "$node_major" -lt 24 ]; then
            install_node=1
        fi
    fi

    if [ "$install_node" -eq 1 ]; then
        log_info "未找到合适的 Node.js (>=24)，准备安装 Node.js 24"
        apt update
        apt install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
        apt update
        apt install -y nodejs
    fi

    if command -v pm2 &> /dev/null; then
        log_info "PM2 已安装: $(pm2 -v)"
    else
        if ! command -v npm &> /dev/null; then
            log_error "未找到 npm，无法安装 PM2"
            exit 1
        fi

        log_info "安装 PM2 (npm -g)..."
        npm install -g pm2
        log_info "PM2 安装完成: $(pm2 -v)"
    fi

    if systemctl list-unit-files | grep -Fq "pm2-root.service"; then
        log_info "PM2 systemd 服务已注册"
        return
    fi

    log_info "配置 PM2 开机自启..."
    pm2 startup systemd -u root --hp /home | grep "sudo" | bash || pm2 startup systemd -u root --hp /home
    pm2 save || true
}

# ============================================
# 配置 Swap
# ============================================
configure_swap() {
    log_step "配置 Swap (物理内存 × 1.5)"

    local total_mem_kb total_mem_mb swap_size_mb swap_size_gb swapfile="/swapfile"

    total_mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    total_mem_mb=$((total_mem_kb / 1024))
    swap_size_mb=$((total_mem_mb * 3 / 2))
    # 向上取整到 GB
    swap_size_gb=$(( (swap_size_mb + 1023) / 1024 ))

    log_info "物理内存: ${total_mem_mb}MB，Swap 目标: ${swap_size_gb}GB (${swap_size_mb}MB)"

    # 检查是否已存在符合要求的 swap
    if [ -f "$swapfile" ] && swapon --show=NAME,SIZE --noheadings | grep -q "$swapfile"; then
        local current_swap_kb current_swap_mb
        current_swap_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
        current_swap_mb=$((current_swap_kb / 1024))
        local diff=$((swap_size_mb - current_swap_mb))
        if [ "${diff#-}" -lt 512 ]; then
            log_info "Swap 已配置且大小合适 (当前: ${current_swap_mb}MB)，跳过"
            return
        fi
        log_info "当前 Swap (${current_swap_mb}MB) 与目标不符，重新配置..."
        swapoff "$swapfile" || true
        rm -f "$swapfile"
    fi

    # 如果有其他 swap 设备挂载在 /swapfile，先关闭
    if swapon --show=NAME --noheadings 2>/dev/null | grep -q "$swapfile"; then
        swapoff "$swapfile" || true
    fi
    rm -f "$swapfile"

    # 创建 swap 文件
    log_info "创建 ${swap_size_gb}GB swap 文件..."
    fallocate -l "${swap_size_gb}G" "$swapfile" || dd if=/dev/zero of="$swapfile" bs=1M count="$swap_size_mb" status=progress
    chmod 600 "$swapfile"
    mkswap "$swapfile"
    swapon "$swapfile"

    # 写入 fstab（幂等）
    if ! grep -q "^${swapfile}\s" /etc/fstab; then
        echo "${swapfile} none swap sw 0 0" >> /etc/fstab
        log_info "已写入 /etc/fstab"
    else
        log_info "/etc/fstab 中已存在 swap 条目"
    fi

    # 设置 swappiness
    sysctl -w vm.swappiness=10 >/dev/null
    if grep -q "^vm.swappiness" /etc/sysctl.conf; then
        sed -i 's/^vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
    else
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi

    log_info "Swap 配置完成: $(swapon --show=NAME,SIZE --noheadings) | swappiness=10"
}

# ============================================
# 配置系统环境
# ============================================
configure_system_env() {
    log_step "配置系统环境"

    cat > /etc/profile.d/sharptier-cms.sh << 'EOF'
export PM2_HOME="/home/.pm2"
EOF
    chmod 644 /etc/profile.d/sharptier-cms.sh
    log_info "已写入 /etc/profile.d/sharptier-cms.sh"
}

# ============================================
# 卸载 apt 版本 Nginx（为源码安装让路）
# ============================================
purge_apt_nginx_if_needed() {
    local apt_nginx_packages=()

    while IFS= read -r package; do
        apt_nginx_packages+=("$package")
    done < <(
        dpkg-query -W -f='${Package} ${Status}\n' 'nginx*' 'libnginx-mod*' 2>/dev/null \
            | awk '$2=="install" && $3=="ok" && $4=="installed" {print $1}' \
            | sort -u
    )

    if [ "${#apt_nginx_packages[@]}" -eq 0 ]; then
        return
    fi

    log_warn "检测到 apt 安装的 Nginx 包，准备卸载以执行源码编译安装"
    systemctl stop nginx 2>/dev/null || true
    apt purge -y "${apt_nginx_packages[@]}"
    apt autoremove -y
}

# ============================================
# 生成 Nginx 主配置（支持 sites-enabled）
# ============================================
write_nginx_main_conf() {
    cat > /etc/nginx/nginx.conf << 'EOF'
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
EOF
}

# ============================================
# 编译安装 Nginx
# ============================================
install_nginx() {
    log_step "编译安装 Nginx $NGINX_VERSION"

    purge_apt_nginx_if_needed

    # 检查是否已安装
    if command -v nginx &> /dev/null; then
        CURRENT_VERSION=$(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+')
        log_warn "Nginx 已安装: $CURRENT_VERSION"
        if [ "$NGINX_REINSTALL" != "1" ]; then
            log_info "跳过重新编译安装（如需强制重装，使用 --reinstall-nginx）"
            return
        fi
        systemctl stop nginx 2>/dev/null || true
    fi

    cd /usr/local/src

    # 下载 Nginx
    if [ ! -f "nginx-${NGINX_VERSION}.tar.gz" ]; then
        wget -q --show-progress http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
    fi
    tar -xzf nginx-${NGINX_VERSION}.tar.gz

    # 下载模块
    log_info "下载 Nginx 模块..."

    [ ! -d "ngx_brotli" ] && git clone --depth 1 --recurse-submodules https://github.com/google/ngx_brotli.git
    [ ! -d "nginx-module-acme" ] && git clone --depth 1 https://github.com/nginx/nginx-acme.git nginx-module-acme
    [ ! -d "headers-more-nginx-module" ] && git clone --depth 1 https://github.com/openresty/headers-more-nginx-module.git
    [ ! -d "ngx_cache_purge" ] && git clone --depth 1 https://github.com/nginx-modules/ngx_cache_purge.git
    [ ! -d "nginx-module-vts" ] && git clone --depth 1 https://github.com/vozlt/nginx-module-vts.git
    [ ! -d "ngx-fancyindex" ] && git clone --depth 1 https://github.com/aperezdc/ngx-fancyindex.git

    # ngx_http_acme_module needs Rust/Cargo
    if ! command -v cargo >/dev/null 2>&1; then
        log_info "Installing Rust toolchain for nginx-acme..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        if [ -f "$HOME/.cargo/env" ]; then
            # shellcheck disable=SC1090
            source "$HOME/.cargo/env"
        fi
    fi

    # 编译
    log_info "编译 Nginx (这可能需要几分钟)..."
    cd nginx-${NGINX_VERSION}

    ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib64/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --user=www-data \
        --group=www-data \
        --with-compat \
        --with-threads \
        --with-file-aio \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_addition_module \
        --with-http_sub_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_auth_request_module \
        --with-http_random_index_module \
        --with-http_secure_link_module \
        --with-http_degradation_module \
        --with-http_slice_module \
        --with-http_stub_status_module \
        --with-http_image_filter_module \
        --with-http_xslt_module \
        --with-http_geoip_module \
        --with-http_perl_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-stream_realip_module \
        --with-stream_geoip_module \
        --with-google_perftools_module \
        --with-pcre \
        --with-pcre-jit \
        --add-module=../nginx-module-acme \
        --add-module=../ngx_brotli \
        --add-module=../headers-more-nginx-module \
        --add-module=../ngx_cache_purge \
        --add-module=../nginx-module-vts \
        --add-module=../ngx-fancyindex

    make -j$(nproc)
    make install

    # 创建 www-data 用户
    id -u www-data &>/dev/null || useradd -r -s /sbin/nologin www-data

    # 创建目录
    mkdir -p /etc/nginx/{conf.d,sites-available,sites-enabled,ssl,acme,snippets}
    mkdir -p /var/log/nginx
    mkdir -p /var/cache/nginx
    chown -R www-data:www-data /var/cache/nginx

    write_nginx_main_conf

    # 创建代理配置
    if [ ! -f /etc/nginx/snippets/proxy_common.conf ]; then
        cat > /etc/nginx/snippets/proxy_common.conf << 'EOF'
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_http_version 1.1;
proxy_buffering off;
proxy_read_timeout 60s;
proxy_send_timeout 60s;
EOF
    fi

    # 生成 ACME 密钥
    if [ ! -f /etc/nginx/acme/account.key ]; then
        openssl genrsa -out /etc/nginx/acme/account.key 4096
        chmod 600 /etc/nginx/acme/account.key
    fi

    # 创建 systemd 服务
    cat > /etc/systemd/system/nginx.service << 'EOF'
[Unit]
Description=Nginx HTTP Server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx
    # Install high command (wrapper for manage.sh)
    cat > /usr/local/bin/high << 'EOF'
#!/bin/bash
if [ -x /home/sharptier-cms/linux_scripts/manage.sh ]; then
  exec /home/sharptier-cms/linux_scripts/manage.sh "$@"
else
  echo "manage.sh not found in /home/sharptier-cms/linux_scripts" >&2
  exit 1
fi
EOF
    chmod +x /usr/local/bin/high


    log_info "Nginx 编译安装完成: $(nginx -v 2>&1)"
}

# ============================================
# 安装结果
# ============================================
show_result() {
    log_step "环境安装完成"

    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}       环境安装成功!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    echo "已安装组件:"
    echo "  ✓ Docker:     $(docker --version | grep -oP '\d+\.\d+\.\d+')"
    echo "  ✓ Nginx:      $(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+')"
    if command -v pm2 &> /dev/null; then
        echo "  ✓ PM2:        $(pm2 -v)"
    else
        echo "  ! PM2:        未安装"
    fi
    echo "  ✓ High 工具:  已安装到系统 (命令: high)"
    echo
    echo "Nginx 模块:"
    echo "  ✓ ACME (自动 SSL 证书)"
    echo "  ✓ Brotli (压缩)"
    echo "  ✓ VTS (流量监控)"
    echo "  ✓ Headers More"
    echo "  ✓ Cache Purge"
    echo "  ✓ Fancy Index"
    echo
    echo "下一步:"
    echo "  1. 运行应用部署脚本:"
    echo "     ./deploy-app-local.sh"
    echo
    echo "  2. 或手动配置 Nginx 和部署应用"
    echo
    echo "配置文件: /home/sharptier-cms/environment-config.env"
    echo -e "${GREEN}============================================${NC}"
}

show_install_summary() {
    local now_human elapsed_seconds elapsed_human
    local docker_version compose_version node_version npm_version pnpm_version pm2_version nginx_version postgresql_version
    local rustc_version cargo_version high_version
    local pkg

    now_human=$(date '+%Y-%m-%d %H:%M:%S')
    elapsed_seconds=$(( $(date +%s) - SCRIPT_START_TS ))
    elapsed_human=$(format_duration "$elapsed_seconds")

    docker_version="未安装"
    if command -v docker >/dev/null 2>&1; then
        docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
    fi

    compose_version="未安装"
    if command -v docker >/dev/null 2>&1; then
        compose_version=$(docker compose version --short 2>/dev/null || echo "已安装(版本获取失败)")
    fi

    node_version="未安装"
    if command -v node >/dev/null 2>&1; then
        node_version=$(node -v)
    fi

    npm_version="未安装"
    if command -v npm >/dev/null 2>&1; then
        npm_version=$(npm -v)
    fi

    pnpm_version="未安装"
    if command -v pnpm >/dev/null 2>&1; then
        pnpm_version=$(pnpm -v)
    fi

    pm2_version="未安装"
    if command -v pm2 >/dev/null 2>&1; then
        pm2_version=$(pm2 -v 2>/dev/null)
    fi

    nginx_version="未安装"
    if command -v nginx >/dev/null 2>&1; then
        nginx_version=$(nginx -v 2>&1 | sed -n 's#nginx version: nginx/\(.*\)#\1#p')
    fi

    postgresql_version="未安装"
    if command -v psql >/dev/null 2>&1; then
        postgresql_version=$(psql --version | awk '{print $3}')
    fi

    rustc_version="未安装"
    if command -v rustc >/dev/null 2>&1; then
        rustc_version=$(rustc -V | awk '{print $2}')
    fi

    cargo_version="未安装"
    if command -v cargo >/dev/null 2>&1; then
        cargo_version=$(cargo -V | awk '{print $2}')
    fi

    high_version="未安装"
    if command -v high >/dev/null 2>&1; then
        high_version="/usr/local/bin/high"
    fi

    echo
    echo -e "${BLUE}==================== 部署软件与运行时长 ====================${NC}"
    print_summary_line "开始时间" "${SCRIPT_START_HUMAN}"
    print_summary_line "完成时间" "${now_human}"
    print_summary_line "总耗时" "${elapsed_human} (${elapsed_seconds} 秒)"
    echo
    echo "部署软件版本:"
    print_summary_line "Nginx (源码安装)" "${nginx_version}"
    print_summary_line "Docker Engine" "${docker_version}"
    print_summary_line "Docker Compose" "${compose_version}"
    print_summary_line "PostgreSQL (psql)" "${postgresql_version}"
    print_summary_line "Node.js" "${node_version}"
    print_summary_line "npm" "${npm_version}"
    print_summary_line "pnpm" "${pnpm_version}"
    print_summary_line "PM2" "${pm2_version}"
    print_summary_line "Rustc" "${rustc_version}"
    print_summary_line "Cargo" "${cargo_version}"
    print_summary_line "high 命令" "${high_version}"

    local swap_info="未配置"
    if swapon --show=SIZE --noheadings 2>/dev/null | head -1 | grep -q .; then
        swap_info="$(swapon --show=NAME,SIZE --noheadings 2>/dev/null | head -1) | swappiness=$(cat /proc/sys/vm/swappiness)"
    fi
    print_summary_line "Swap" "${swap_info}"
    echo
    echo "APT 依赖版本:"
    for pkg in "${SYSTEM_DEP_PACKAGES[@]}"; do
        print_summary_line "$pkg" "$(get_dpkg_version "$pkg")"
    done
    for pkg in "${DOCKER_PACKAGES[@]}"; do
        print_summary_line "$pkg" "$(get_dpkg_version "$pkg")"
    done
    print_summary_line "nodejs" "$(get_dpkg_version "nodejs")"
    echo -e "${BLUE}=========================================================${NC}"
}

# ============================================
# 主函数
# ============================================
main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════╗"
    echo "║     sharptier-cms 环境安装脚本                  ║"
    echo "║     Ubuntu 24.04 / Debian 13              ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"

    parse_args "$@"
    check_root
    check_system
    collect_config
    install_dependencies
    configure_swap
    install_docker
    install_pm2
    configure_system_env
    install_nginx
    show_result
    show_install_summary
}

# 运行主函数
main "$@"
