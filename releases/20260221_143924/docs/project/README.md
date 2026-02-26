# Template SharpTier CMS (Payload + Next)

## 项目概述
`/home/template-sharptier-cms` 基于官方示例仓库 `payloadcms/reusable-content-example` 搭建，保留其 **On-demand Revalidation**、Draft/Live Preview 能力，并改造为 SharpTier 的本地部署体系：

- 应用：Payload CMS + Next.js（单应用）
- 数据库：本机 PostgreSQL 18（新建独立库）
- 反向代理：Nginx（域名 `template.sharptier.com`）
- 进程管理：PM2
- 运维：`linux_scripts/`（发布、回滚、备份、恢复、更新）

## 当前域名与端口
- 生产域名：`https://template.sharptier.com`
- 本地服务端口：`127.0.0.1:3001`
- 管理后台：`https://template.sharptier.com/admin`
- API：`https://template.sharptier.com/api`
- 健康检查：`https://template.sharptier.com/api/health`

## 目录结构
- `src/`：Payload + Next 业务代码（来自 reusable-content-example）
- `shared/`：环境变量源（`app.env`、`deploy.env`）
- `scripts/`：辅助脚本（内存计算等）
- `linux_scripts/`：部署和运维脚本
- `linux_scripts/conf/template-sharptier-cms.conf`：Nginx 站点模板
- `releases/`：发布目录
- `current`：当前运行版本软链
- `logs/`：运行日志

## 快速开始（开发）
1. 准备环境变量
   - `cp .env.example .env`
   - 编辑 `.env`，确保 `DATABASE_URI`、`PAYLOAD_SECRET`、`NEXT_PUBLIC_SERVER_URL` 正确
2. 安装依赖
   - `pnpm install`
3. 生成 Payload 类型与 import map
   - `pnpm generate:types`
   - `pnpm generate:importmap`
4. 初始化数据库结构
   - `pnpm payload migrate`
5. 启动开发环境
   - `pnpm dev`

## 一键部署（本机）
建议 root 执行：

```bash
cd /home/template-sharptier-cms
sudo ./linux_scripts/deploy-app-local.sh template.sharptier.com
```

该脚本会执行：
- 读取 `shared/deploy.env` 与 `shared/app.env`
- 渲染 Nginx 站点配置并重载
- 执行发布构建（`linux_scripts/manage-release-build-and-switch.sh`）
- 使用 PM2 启动/重载 `template-sharptier-cms`
- 验证本地健康检查 `http://127.0.0.1:3001/api/health`

## 数据库说明
本项目使用 PostgreSQL（非 Docker）并已规划独立库：
- DB 名称：`template_sharptier_cms`
- DB 用户：`templatecms_user`

详细配置见：
- `shared/app.env`
- `shared/deploy.env`

## 可用运维命令
- `./linux_scripts/manage.sh status`
- `./linux_scripts/manage.sh start`
- `./linux_scripts/manage.sh restart`
- `./linux_scripts/manage.sh logs`
- `./linux_scripts/manage.sh backup`
- `./linux_scripts/manage.sh restore <backup_file>`
- `./linux_scripts/manage.sh update`

## 文档索引
- `README.md`：项目总览
- `DEVELOPER_GUIDE.md`：开发指南
- `DEV_DEPLOY_SOP.md`：部署与回滚 SOP
- `ISSUE_TRACKER.md`：问题追踪模板
- `MULTI_SITE_PORT_AND_ROUTING.md`：多站点端口规划与容器/K8s 服务名路由说明
