# RustFS 部署指南

本文档详细记录了在本项目中集成 RustFS (S3 兼容高性能对象存储) 的完整方案。

## 🏗️ 架构概览

本项目利用 RustFS 替代传统的 AWS S3 或 Cloudflare R2，实现高性能的自主可控媒体存储。

| 组件 | 端口 (Host) | 容器端口 | 用途 |
|------|-------------|----------|------|
| **S3 API** | `9000` | `9000` | 供 PayloadCMS 和 CLI 工具连接 |
| **Console** | `9001` | `9001` | Web 管理控制台 (浏览器访问) |

*   **数据持久化**: 挂载于 Docker Volume `rustfs-data`
*   **网络模式**: 默认 Bridge 模式，通过端口映射暴露服务

---

## 🚀 部署步骤

### 1. Docker Compose 部署

RustFS 通过主 `docker-compose.yml` 的 `storage` profile 启动（不单独维护 compose 文件）。

**启动服务**:
```bash
docker compose -f docker-compose.yml --profile storage up -d rustfs
```

**停止服务**:
```bash
docker compose -f docker-compose.yml --profile storage down
```

**完全重置 (慎用 - 会删除数据)**:
```bash
docker compose -f docker-compose.yml --profile storage down -v
```

### 2. 初始化 Bucket

虽然可以通过 Web 控制台手动创建，但我们提供了自动化脚本（推荐）：

```bash
# 执行部署脚本，自动使用 amazon/aws-cli 初始化（推荐）
sudo ./linux_scripts/deploy-rustfs.sh
```

**备用方式 (手动)**:
如果你需要使用旧版脚本（不推荐）：
```bash
# 需要 Node.js 环境
node scripts/setup-rustfs-bucket.mjs
```

该脚本会自动检测并创建名为 `sharptier-cms-media` 的存储桶。

### 3. PayloadCMS 集成配置

在 `.env` 文件中配置 S3 适配器：

```dotenv
# 启用 S3 模式
MEDIA_STORAGE=s3

# 连接配置
S3_BUCKET=sharptier-cms-media
S3_ACCESS_KEY_ID=rustfsadmin
S3_SECRET_ACCESS_KEY=CHANGE_ME
S3_REGION=us-east-1
S3_ENDPOINT=http://localhost:9000
S3_FORCE_PATH_STYLE=true
```

重要参数说明：
*   `S3_ENDPOINT`: 必须指向 API 端口 (9000)，不是控制台端口。
*   `S3_FORCE_PATH_STYLE`: **必须为 true**。RustFS/MinIO 需要此模式 (即 `http://host/bucket`)，而不是 AWS 默认的子域名模式 (`http://bucket.host`)。

---

## 🔧 管理与验证

### 访问 Web 控制台
*   **地址**: [http://localhost:9001/rustfs/console/index.html](http://localhost:9001/rustfs/console/index.html)
*   **账号**: `rustfsadmin`
*   **密码**: `CHANGE_ME`

### 常见问题 (Troubleshooting)

#### Q: 端口冲突 (Address already in use)
通常是因为 Portainer 或其他服务占用了 9000 端口。
**解决**: 修改 `docker-compose.rustfs.yml` 中的映射，例如 `"9002:9000"`，同时记得更新 `.env` 中的 `S3_ENDPOINT`。

#### Q: 解密失败 / 容器无法启动
如果修改了 `RUSTFS_SECRET_KEY` 变量名或值，旧的加密数据将无法读取，导致容器 Crash。
**解决**: 除非你能找回旧密码，否则必须清空数据卷重来：`docker compose ... down -v`。

#### Q: PayloadCMS 连接报错 (ECONNREFUSED)
**检查**:
1. 容器是否健康 (`docker ps` 显示 `healthy`)?
2. `.env` 中的 `S3_ENDPOINT` 端口是否正确 (是 API 端口，不是 Console 端口)?
3. 修改 `.env` 后是否重启了 Next.js 服务? (热重载无效)

---

## 📚 常用命令备忘

```bash
# 查看实时日志
docker logs -f rustfs

# 检查健康状态
docker inspect --format='{{json .State.Health}}' rustfs

# 进入容器内部
docker exec -it rustfs sh
```
