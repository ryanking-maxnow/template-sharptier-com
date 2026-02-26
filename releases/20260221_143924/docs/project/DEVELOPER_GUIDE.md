# DEVELOPER GUIDE

## 1. 目标
该项目是 `reusable-content-example` 的本地化生产版本，重点是：
- 保留官方内容模型与 On-demand Revalidation 机制
- 使用本机 PostgreSQL 替代 MongoDB
- 使用 Nginx + PM2 + Bash 脚本实现稳定发布

## 2. 环境要求
- Node.js >= 24
- pnpm >= 10
- PostgreSQL >= 18（本机服务）
- Nginx（支持当前模板配置）
- PM2

## 3. 环境变量策略
环境分层：
- 开发：项目根 `.env`
- 部署：`shared/deploy.env`（部署参数）+ `shared/app.env`（应用运行参数）

关键变量：
- `DATABASE_URI`
- `PAYLOAD_SECRET`
- `NEXT_PUBLIC_SERVER_URL`
- `CRON_SECRET`
- `PREVIEW_SECRET`

## 4. 本地开发流程
1. `cp .env.example .env`
2. 设置 `DATABASE_URI=postgresql://templatecms_user:<password>@127.0.0.1:5432/template_sharptier_cms`
3. `pnpm install`
4. `pnpm payload migrate`
5. `pnpm dev`
6. 打开 `http://localhost:3000`

## 5. 数据库迁移规范
- 新增/变更字段后，先本地验证再提交迁移
- 生产发布前执行：`pnpm payload migrate`
- 推荐流程：
  1. 本地改 schema
  2. 生成迁移：`pnpm payload migrate:create`
  3. 提交迁移文件
  4. 部署时执行迁移

## 6. 发布架构说明
发布脚本采用“目录发布 + 软链切换”：
- 构建产物进入 `releases/<timestamp>`
- `current` 软链指向当前版本
- PM2 始终从 `current` 启动

优点：
- 回滚快
- 与代码目录解耦
- 支持保留最近 N 个版本

## 7. 代码约定
- 所有环境变量只在 `shared/*.env` 与 `.env` 维护
- 不将真实密钥提交到 git
- 运维入口统一走 `linux_scripts/manage.sh`
- 修改部署逻辑时同时更新 `DEV_DEPLOY_SOP.md`

## 8. 常见问题
1. 启动后无法连接数据库
   - 检查 `DATABASE_URI` 中用户、密码、库名
   - 确认 `sudo -u postgres psql -l` 可见目标数据库

2. `/admin` 可访问但页面资源异常
   - 检查 Nginx 反代是否指向 `127.0.0.1:3000`
   - 检查 PM2 进程状态

3. 内容发布后前台没更新
   - 检查 `afterChange` hooks 是否执行
   - 查看应用日志确认 revalidation 无报错

## 9. 建议协作流程
1. 功能开发
2. 本地运行与验证
3. 更新文档（README / SOP / ISSUE_TRACKER）
4. 提交代码
5. 执行部署脚本
6. 验证域名、管理后台、健康检查
