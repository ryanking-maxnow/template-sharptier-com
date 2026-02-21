#!/bin/bash
export PM2_HOME="${PM2_HOME:-/home/.pm2}"
#
# 数据库导入脚本
#
# 使用方法:
#   chmod +x deploy-import-database.sh
#   sudo ./deploy-import-database.sh [sql_file_path]
#
# 示例:
#   sudo ./deploy-import-database.sh /home/sharptier-cms/backups/database.sql
#   sudo ./deploy-import-database.sh  # 默认使用 /home/sharptier-cms/backups/database.sql

set -e

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# ============================================
# 检查 root 权限
# ============================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        log_info "使用: sudo ./deploy-import-database.sh [sql_file_path]"
        exit 1
    fi
}

# ============================================
# 加载配置
# ============================================
load_config() {
    log_step "加载配置"

    if [ ! -f "/home/sharptier-cms/deploy.env" ]; then
        log_error "配置文件不存在: /home/sharptier-cms/deploy.env"
        log_info "请先运行 setup-environment.sh 和 deploy-app-local.sh"
        exit 1
    fi

    source /home/sharptier-cms/deploy.env
    log_info "配置加载成功"
}

# ============================================
# 检查 PostgreSQL 容器
# ============================================
check_postgres() {
    log_step "检查 PostgreSQL 容器"

    if ! docker ps --format '{{.Names}}' | grep -q '^sharptier-postgres$'; then
        log_error "PostgreSQL 容器未运行"
        log_info "请先运行 deploy-app-local.sh 启动 PostgreSQL"
        exit 1
    fi

    log_info "PostgreSQL 容器运行中"
}

# ============================================
# 导入数据库
# ============================================
import_database() {
    local sql_file=$1

    log_step "导入数据库"

    # 如果没有指定文件，询问用户
    if [ -z "$sql_file" ]; then
        local default_path="/home/sharptier-cms/backups/database.sql"
        read -p "数据库备份文件路径 [$default_path]: " sql_file
        sql_file=${sql_file:-$default_path}
    fi

    # 检查 SQL 文件是否存在
    if [ ! -f "$sql_file" ]; then
        log_error "SQL 文件不存在: $sql_file"
        exit 1
    fi

    log_info "SQL 文件: $sql_file"
    log_info "数据库: $DB_NAME"
    log_info "用户: $DB_USER"
    echo

    # 询问确认
    log_warn "此操作将删除现有数据库并重新导入"
    read -p "确认继续? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "操作已取消"
        exit 0
    fi

    # 停止应用服务（如果在运行）
    log_info "停止应用服务..."
    if command -v pm2 &> /dev/null; then
        if pm2 list 2>/dev/null | grep -q "sharptier-cms"; then
            pm2 stop sharptier-cms || true
        fi
    elif systemctl list-unit-files | grep -q "sharptier-cms.service"; then
        systemctl stop sharptier-cms || true
    fi

    # 强制断开所有连接
    log_info "强制断开所有连接..."
    docker exec sharptier-postgres psql -U "$DB_USER" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" || true

    # 删除现有数据库
    log_info "删除现有数据库..."
    docker exec sharptier-postgres psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS \"$DB_NAME\";" postgres || true

    # 创建新数据库
    log_info "创建新数据库..."
    docker exec sharptier-postgres psql -U "$DB_USER" -c "CREATE DATABASE \"$DB_NAME\";" postgres

    # 导入 SQL 文件
    log_info "导入数据..."
    docker exec -i sharptier-postgres psql -U "$DB_USER" -d "$DB_NAME" < "$sql_file"

    if [ $? -eq 0 ]; then
        log_info "数据库导入成功"
    else
        log_error "数据库导入失败"
        exit 1
    fi

    # 重启应用服务
    log_info "启动应用服务..."
    if command -v pm2 &> /dev/null; then
        if pm2 list 2>/dev/null | grep -q "sharptier-cms"; then
            pm2 restart sharptier-cms || true
        elif [ -f /home/sharptier-cms/payloadcms/ecosystem.config.cjs ]; then
            pm2 start /home/sharptier-cms/payloadcms/ecosystem.config.cjs || true
        fi
        pm2 save || true
    elif systemctl list-unit-files | grep -q "sharptier-cms.service"; then
        systemctl start sharptier-cms
        sleep 3
        systemctl status sharptier-cms --no-pager || true
    fi
}

# ============================================
# 显示使用说明
# ============================================
show_usage() {
    echo "使用方法:"
    echo "  sudo ./deploy-import-database.sh [sql_file_path]"
    echo ""
    echo "示例:"
    echo "  sudo ./deploy-import-database.sh /home/sharptier-cms/backups/database.sql"
    echo "  sudo ./deploy-import-database.sh  # 交互式输入文件路径"
    echo ""
    echo "说明:"
    echo "  如果不指定文件路径，脚本将提示您输入"
    echo "  默认路径: /home/sharptier-cms/backups/database.sql"
    echo ""
}

# ============================================
# 主函数
# ============================================
main() {
    check_root

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi

    load_config
    check_postgres
    import_database "$1"

    log_step "数据库导入完成"
    log_info "数据库已成功导入到 PostgreSQL 容器"
}

main "$@"
