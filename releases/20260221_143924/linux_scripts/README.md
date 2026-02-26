# linux_scripts

面向 `template-sharptier-cms` 的运维脚本集合（单 Payload + Next 架构）。

## 入口脚本
- `deploy-app-local.sh`：首次部署 / 重部署（Nginx + PM2 + 发布）
- `manage-release-build-and-switch.sh`：构建发布并原子切换 `current`
- `manage-update.sh`：git 更新 + 发布 + 健康检查 + 自动回滚
- `manage-backup.sh`：数据库与配置备份（支持 `--db-only`）
- `manage-restore.sh`：从 SQL/归档恢复
- `manage.sh`：日常运维命令入口

## 配置模板
- `conf/template-sharptier-cms.conf`：Nginx 模板（`template.sharptier.com`）

## 约束
- 默认部署根目录：`/home/template-sharptier-cms`
- 默认运行端口：`127.0.0.1:3000`
- 默认 PM2 进程名：`template-sharptier-cms`
