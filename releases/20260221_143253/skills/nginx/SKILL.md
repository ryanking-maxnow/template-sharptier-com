---
name: Nginx Configuration
description: How to configure Nginx for static site serving, reverse proxy to Payload CMS, SSL, caching, and Brotli compression in this project.
---

# Nginx Configuration Skill

## Overview

In this project, Nginx serves two roles:
1. **Static file server** for Astro-generated HTML/CSS/JS from `astro-releases/current/`.
2. **Reverse proxy** forwarding `/admin` and `/api` to the PM2-managed Payload process on `127.0.0.1:3000`.

## Project Architecture

```
Internet → Nginx (port 443/80)
             ├── / → astro-releases/current/ (static files)
             ├── /admin → proxy_pass http://127.0.0.1:3000
             └── /api   → proxy_pass http://127.0.0.1:3000
```

## Config File Location

- Config template: `linux_scripts/conf/sharptier-cms.conf`
- Active config: `/etc/nginx/sites-enabled/sharptier-cms.conf`
- Nginx binary: source-built at `/usr/sbin/nginx` (version 1.29.5)

## Core Configuration Pattern

```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    # SSL (managed by Certbot / nginx-acme)
    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # Astro static files — served from atomic release symlink
    root /home/sharptier-cms/astro-releases/current;
    index index.html;

    # Static asset caching (hashed filenames are immutable)
    location /_astro/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # HTML pages — short cache, revalidate on deploy
    location / {
        try_files $uri $uri/index.html $uri.html =404;
        add_header Cache-Control "public, max-age=300, must-revalidate";
    }

    # Payload CMS Admin Panel
    location /admin {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Payload REST API
    location /api {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP → HTTPS redirect
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}
```

## Built-in Modules (Source Build)

| Module | Purpose |
| :--- | :--- |
| `nginx-acme` | Automated SSL via ACME/Let's Encrypt |
| `ngx_brotli` | Brotli compression (better than gzip for text) |
| `headers-more` | Custom response headers |
| `ngx_cache_purge` | Cache invalidation API |
| `nginx-module-vts` | Virtual host traffic status / monitoring |
| `ngx-fancyindex` | Directory listing (dev/debug) |

## Brotli Compression

```nginx
brotli on;
brotli_comp_level 6;
brotli_types text/html text/css application/javascript application/json image/svg+xml;
```

## Security Headers

```nginx
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "frame-ancestors 'self' https://cms.example.com;" always;
```

> **Note**: `frame-ancestors` must include the Payload Admin domain for Live Preview to work in its iframe.

## Common Commands

```bash
# Test configuration syntax
nginx -t

# Reload (zero-downtime)
nginx -s reload

# Check running status
systemctl status nginx

# View error log
tail -f /var/log/nginx/error.log

# View access log
tail -f /var/log/nginx/access.log
```

## Atomic Deploy Integration

When `manage-release-build-and-switch.sh` runs:
1. New Astro build is copied to `astro-releases/<timestamp>/`
2. Symlink `astro-releases/current` is atomically updated
3. `nginx -s reload` picks up the new content instantly (no restart needed)

## Official Documentation
- Nginx Core: https://nginx.org/en/docs/
- Proxy Pass: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- SSL: https://nginx.org/en/docs/http/ngx_http_ssl_module.html
