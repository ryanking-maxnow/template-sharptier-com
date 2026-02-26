---
name: Docker and Docker Compose
description: How to use Docker and Docker Compose for managing PostgreSQL, RustFS (S3-compatible storage), and development containers in this project.
---

# Docker & Docker Compose Skill

## Overview

Docker is used in this project for **data services only** — not for the application itself. The application (Payload + Astro) runs natively on Node.js.

| Container | Purpose | Profile |
| :--- | :--- | :--- |
| PostgreSQL 18 | Primary database | Default |
| RustFS | S3-compatible object storage | `storage` |

## docker-compose.yml Structure

```yaml
services:
  postgres:
    image: postgres:18-alpine
    container_name: sharptier-postgres
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - postgres_data:/var/lib/postgresql/data

  rustfs:
    image: rustfs/rustfs:latest
    container_name: sharptier-rustfs
    profiles: [storage]
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      RUSTFS_ROOT_USER: ${S3_ACCESS_KEY}
      RUSTFS_ROOT_PASSWORD: ${S3_SECRET_KEY}
    volumes:
      - rustfs_data:/data

volumes:
  postgres_data:
  rustfs_data:
```

## Common Commands

```bash
# Start all default services (PostgreSQL)
docker compose up -d

# Start with storage profile (PostgreSQL + RustFS)
docker compose --profile storage up -d

# Stop all services
docker compose down

# Stop and remove volumes (⚠️ DESTRUCTIVE)
docker compose down -v

# View logs
docker compose logs -f postgres
docker compose logs -f rustfs

# Check status
docker compose ps

# Restart a specific service
docker compose restart postgres

# Execute command inside container
docker compose exec postgres psql -U sharptier -d sharptier_cms
```

## RustFS (S3-Compatible Storage)

Initialize buckets after first start:
```bash
bash linux_scripts/deploy-rustfs.sh
```

This uses the AWS CLI container to create the media bucket:
```bash
docker run --rm --network host amazon/aws-cli \
  --endpoint-url http://localhost:9000 \
  s3 mb s3://sharptier-media
```

## Health Checks

```bash
# Check PostgreSQL
docker compose exec postgres pg_isready -U sharptier

# Check RustFS
curl -s http://localhost:9000/minio/health/ready
```

## Data Persistence

- PostgreSQL data: Docker volume `postgres_data`
- RustFS data: Docker volume `rustfs_data`
- **Backups**: Use `linux_scripts/manage-backup.sh` (exports via `pg_dump`)

## Official Documentation
- Docker: https://docs.docker.com/engine/
- Docker Compose: https://docs.docker.com/compose/
- PostgreSQL Docker Image: https://hub.docker.com/_/postgres
