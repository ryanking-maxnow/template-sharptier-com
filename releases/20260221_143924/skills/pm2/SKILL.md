---
name: PM2 Process Management
description: How to use PM2 for managing the Payload CMS Node.js process — cluster mode, zero-downtime reload, logs, monitoring, and systemd integration.
---

# PM2 Process Management Skill

## Overview

PM2 manages the **Payload CMS process only** (Next.js runtime hosting `/admin` and `/api`). Astro is static and served directly by Nginx — no PM2 involvement.

## Ecosystem Config

```javascript
// ecosystem.config.cjs
module.exports = {
  apps: [{
    name: 'sharptier-cms',
    cwd: '/home/sharptier-cms/releases/current',
    script: 'node_modules/.bin/next',
    args: 'start -p 3000',
    instances: 'max',        // Use all CPUs - 1
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
    },
    env_file: '/home/sharptier-cms/shared/app.env',
    max_memory_restart: '512M',
    watch: false,
    // Logging
    error_file: '/home/sharptier-cms/logs/pm2-error.log',
    out_file: '/home/sharptier-cms/logs/pm2-out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
  }],
}
```

## Common Commands

```bash
# Start/Restart with ecosystem file
pm2 start ecosystem.config.cjs

# Zero-downtime reload (cluster mode)
pm2 reload sharptier-cms

# Hard restart (if reload fails)
pm2 restart sharptier-cms

# Stop
pm2 stop sharptier-cms

# Delete from PM2 process list
pm2 delete sharptier-cms

# View status
pm2 status

# View logs (live tail)
pm2 logs sharptier-cms

# View logs (last 100 lines)
pm2 logs sharptier-cms --lines 100

# Monitor (interactive dashboard)
pm2 monit

# Save current process list (survives reboot)
pm2 save

# Resurrect saved processes
pm2 resurrect
```

## Systemd Integration

```bash
# Register PM2 to start on boot (run once)
pm2 startup systemd
# Then run the command it outputs

# Save current process list
pm2 save
```

## Health Check Script

`linux_scripts/pm2-check-and-start.sh` can be used as a cron job:
```bash
# Crontab entry (check every 5 minutes)
*/5 * * * * /home/sharptier-cms/linux_scripts/pm2-check-and-start.sh
```

## Deployment Flow

1. `manage-release-build-and-switch.sh` builds Payload in `releases/<timestamp>/`
2. Updates `releases/current` symlink
3. Runs `pm2 reload sharptier-cms` (zero-downtime in cluster mode)

## Troubleshooting

```bash
# Check if PM2 daemon is running
pm2 ping

# Reset restart counter
pm2 reset sharptier-cms

# View detailed process info
pm2 describe sharptier-cms

# Flush logs
pm2 flush
```

## Official Documentation
- PM2 Documentation: https://pm2.keymetrics.io/docs/usage/quick-start/
- Cluster Mode: https://pm2.keymetrics.io/docs/usage/cluster-mode/
- Ecosystem File: https://pm2.keymetrics.io/docs/usage/application-declaration/
