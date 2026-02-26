#!/bin/bash
# =============================================================================
# Docker 数据导出脚本
# 导出 PostgreSQL 数据库和上传文件，用于迁移到 VPS
# =============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
APP_DIR="/home/sharptier-cms"
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="sharptier-cms-backup-${TIMESTAMP}"
POSTGRES_CONTAINER="sharptier-postgres"

# 加载部署配置（优先 shared/deploy.env）
if [ -f "${APP_DIR}/shared/deploy.env" ]; then
    # shellcheck disable=SC1091
    source "${APP_DIR}/shared/deploy.env"
elif [ -f "${APP_DIR}/deploy.env" ]; then
    # shellcheck disable=SC1091
    source "${APP_DIR}/deploy.env"
fi

POSTGRES_USER="${POSTGRES_USER:-${DB_USER:-payload}}"
POSTGRES_DB="${POSTGRES_DB:-${DB_NAME:-payload}}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  sharptier CMS 数据导出工具${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "数据库用户: ${POSTGRES_USER}"
echo "数据库名称: ${POSTGRES_DB}"
echo ""

# 创建备份目录
mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}"

# -----------------------------------------------------------------------------
# 1. 导出 PostgreSQL 数据库
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/3] 导出 PostgreSQL 数据库...${NC}"

# 检查容器是否运行
if ! docker ps --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$"; then
    echo -e "${RED}错误: PostgreSQL 容器未运行！${NC}"
    echo "请先启动容器: docker-compose up -d postgres"
    exit 1
fi

# 使用 pg_dump 导出数据库
docker exec ${POSTGRES_CONTAINER} pg_dump -U ${POSTGRES_USER} -d ${POSTGRES_DB} \
    --clean --if-exists --no-owner --no-privileges \
    > "${BACKUP_DIR}/${BACKUP_NAME}/database.sql"

echo -e "${GREEN}✓ 数据库导出完成${NC}"

# -----------------------------------------------------------------------------
# 2. 导出上传文件 (uploads volume)
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/3] 导出上传文件...${NC}"

# 检查 uploads volume 是否存在
if docker volume ls --format '{{.Name}}' | grep -q "sharptier-cms-uploads"; then
    # 使用临时容器导出 volume 数据
    docker run --rm \
        -v sharptier-cms-uploads:/data:ro \
        -v "$(pwd)/${BACKUP_DIR}/${BACKUP_NAME}":/backup \
        alpine tar czf /backup/uploads.tar.gz -C /data .
    echo -e "${GREEN}✓ 上传文件导出完成${NC}"
else
    # 兼容 Native 部署下的本地目录
    MEDIA_PATHS=(
        "${APP_DIR}/current/media"
        "${APP_DIR}/media"
        "${APP_DIR}/current/public/uploads"
        "${APP_DIR}/app/public/uploads"
    )

    media_exported=false
    for media_path in "${MEDIA_PATHS[@]}"; do
        if [ -d "${media_path}" ]; then
            tar czf "${BACKUP_DIR}/${BACKUP_NAME}/uploads.tar.gz" -C "$(dirname "${media_path}")" "$(basename "${media_path}")"
            echo -e "${GREEN}✓ 本地媒体目录导出完成: ${media_path}${NC}"
            media_exported=true
            break
        fi
    done

    if [ "${media_exported}" = false ]; then
        echo -e "${YELLOW}⚠ 未找到 uploads volume 或本地媒体目录，跳过${NC}"
    fi
fi

# -----------------------------------------------------------------------------
# 3. 打包所有备份文件
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/3] 打包备份文件...${NC}"

cd "${BACKUP_DIR}"
tar czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"
rm -rf "${BACKUP_NAME}"
cd ..

# 显示备份信息
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  导出完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "备份文件: ${YELLOW}${BACKUP_FILE}${NC}"
echo -e "文件大小: ${YELLOW}${BACKUP_SIZE}${NC}"
echo ""
echo -e "传输到 VPS 的命令:"
echo -e "${YELLOW}  scp ${BACKUP_FILE} user@your-vps:/path/to/destination/${NC}"
echo ""
echo -e "在 VPS 上导入数据:"
echo -e "${YELLOW}  ./deploy-import-database.sh ${BACKUP_NAME}/database.sql${NC}"
