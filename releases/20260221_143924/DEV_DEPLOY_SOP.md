# DEV DEPLOY SOP

## 0. 适用范围
适用于 `template-sharptier-cms` 在单机环境下的部署、更新、回滚、备份恢复。

## 1. 前置检查
1. 确保目录存在：`/home/template-sharptier-cms`
2. 确保 PostgreSQL 运行：`systemctl is-active postgresql`
3. 确保 Nginx 安装可用：`nginx -v`
4. 确保 PM2 可用：`pm2 -v`
5. 确保环境文件存在：
   - `shared/deploy.env`
   - `shared/app.env`

## 2. 初次部署
```bash
cd /home/template-sharptier-cms
sudo ./linux_scripts/deploy-app-local.sh template.sharptier.com
```

成功后验证：
```bash
curl -I http://127.0.0.1:3001/api/health
curl -I http://template.sharptier.com
curl -I https://template.sharptier.com/admin
```

## 3. 日常更新
```bash
cd /home/template-sharptier-cms
sudo ./linux_scripts/manage-update.sh
```

指定分支/标签：
```bash
sudo ./linux_scripts/manage-update.sh <git-ref>
```

## 4. 回滚
自动回滚（更新失败时脚本会尝试）：
- 回到更新前 `current` 软链

手动回滚到上一个版本：
```bash
sudo ./linux_scripts/manage-update.sh --rollback
```

## 5. 备份
完整备份：
```bash
sudo ./linux_scripts/manage-backup.sh
```

仅数据库：
```bash
sudo ./linux_scripts/manage-backup.sh --db-only
```

备份目录：
- `/home/template-sharptier-cms/backups/database`
- `/home/template-sharptier-cms/backups/files`
- `/home/template-sharptier-cms/backups/archives`

## 6. 恢复
```bash
sudo ./linux_scripts/manage-restore.sh /home/template-sharptier-cms/backups/database/<file>.sql.gz
```

或恢复完整归档：
```bash
sudo ./linux_scripts/manage-restore.sh /home/template-sharptier-cms/backups/archives/<file>.tar.gz
```

## 7. 常用运维命令
```bash
./linux_scripts/manage.sh status
./linux_scripts/manage.sh logs
./linux_scripts/manage.sh restart
./linux_scripts/manage.sh backup
```

## 8. 发布验收清单
1. `http://127.0.0.1:3001/api/health` 返回 2xx
2. `https://template.sharptier.com/admin` 可打开
3. 前台首页可访问
4. 新增/编辑页面后前台可触发更新（on-demand revalidation）
5. `pm2 list` 显示 `template-sharptier-cms` 为 `online`

## 9. 安全注意事项
- `shared/*.env` 权限建议 `600`
- 不在仓库提交真实密钥
- 回滚前先执行数据库备份
- 对生产库执行迁移前先做一次 `--db-only` 备份
