---
name: PostgreSQL Database
description: How to manage PostgreSQL 18.x — installation, user/database setup, backups, migrations, performance tuning, and Docker vs native deployment.
---

# PostgreSQL Database Skill

## Overview

PostgreSQL 18.2 is the primary relational database for Payload CMS. In this project it is installed **natively via APT** (not Docker), using the PostgreSQL official repository.

## Installation (via deploy script)

```bash
# The deploy-setup-environment.sh script does this:
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y postgresql-18
```

## Connection

- **Connection string format**: `postgresql://USER:PASSWORD@localhost:5432/DATABASE`
- **Env variable**: `DATABASE_URL` in `shared/app.env`
- **Payload adapter**: `@payloadcms/db-postgres`

```typescript
// payload.config.ts
import { postgresAdapter } from '@payloadcms/db-postgres'

export default buildConfig({
  db: postgresAdapter({
    pool: { connectionString: process.env.DATABASE_URL },
    push: false, // CRITICAL: always false in production
  }),
})
```

## Common Commands

```bash
# Connect to database
sudo -u postgres psql -d sharptier_cms

# List databases
sudo -u postgres psql -l

# List tables in current database
\dt

# Describe table schema
\d+ table_name

# Check active connections
SELECT * FROM pg_stat_activity WHERE datname = 'sharptier_cms';

# Check database size
SELECT pg_size_pretty(pg_database_size('sharptier_cms'));

# Check table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

## Backup and Restore

```bash
# Backup (plain SQL)
sudo -u postgres pg_dump sharptier_cms > backup.sql

# Backup (custom format, compressed)
sudo -u postgres pg_dump -Fc sharptier_cms > backup.dump

# Restore from SQL
sudo -u postgres psql sharptier_cms < backup.sql

# Restore from custom format
sudo -u postgres pg_restore -d sharptier_cms backup.dump
```

Or use the project scripts:
```bash
bash linux_scripts/manage-backup.sh
bash linux_scripts/manage-restore.sh
bash linux_scripts/manage-export-database.sh
```

## User and Database Setup

```sql
-- Create user
CREATE USER sharptier WITH PASSWORD 'your_password';

-- Create database
CREATE DATABASE sharptier_cms OWNER sharptier;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE sharptier_cms TO sharptier;
```

## Performance Configuration

Key settings in `postgresql.conf`:

```ini
# Memory (adjust based on server RAM)
shared_buffers = 256MB          # 25% of total RAM
effective_cache_size = 768MB    # 75% of total RAM
work_mem = 16MB
maintenance_work_mem = 128MB

# WAL
wal_level = replica
max_wal_size = 1GB

# Connections
max_connections = 100

# Logging
log_min_duration_statement = 1000  # Log queries > 1s
```

## Payload Migrations

See the `/migrate` workflow. Key points:
- `push: false` enforced — all schema changes require explicit migration files.
- Migrations are SQL files in `payloadcms/src/migrations/`.
- Run with `pnpm --dir payloadcms payload migrate`.

## Official Documentation
- PostgreSQL 18: https://www.postgresql.org/docs/18/index.html
- pg_dump: https://www.postgresql.org/docs/18/app-pgdump.html
- Performance Tuning: https://www.postgresql.org/docs/18/runtime-config-resource.html
