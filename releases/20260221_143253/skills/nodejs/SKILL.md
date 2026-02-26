---
name: Node.js Runtime
description: How to manage Node.js 24.x LTS — installation, version management, memory tuning, debugging, and ES module patterns used in this project.
---

# Node.js Runtime Skill

## Overview

Node.js 24.x LTS is the runtime for both Payload CMS (production) and Astro (build-time). It is installed via NodeSource APT repository, not nvm.

## Installation (via deploy script)

```bash
# deploy-setup-environment.sh does this:
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs
```

Verify:
```bash
node --version   # v24.13.1
npm --version    # bundled
```

## pnpm (Package Manager)

This project uses `pnpm` exclusively (not npm/yarn):

```bash
# Enable via corepack (bundled with Node.js)
corepack enable pnpm

# Install dependencies (frozen lockfile for CI/production)
pnpm install --frozen-lockfile

# Workspace commands
pnpm -r build                             # Build all workspace packages
pnpm --dir payloadcms dev                  # Run dev in specific package
pnpm --dir astro-frontend build            # Build specific package
pnpm --filter payloadcms add <package>     # Add dep to specific package
```

## Memory Management

Node.js defaults may not be enough for large builds:

```bash
# Check current heap limit
node -e "console.log(v8.getHeapStatistics().heap_size_limit / 1024 / 1024 + ' MB')"

# Increase for builds (in scripts or env)
export NODE_OPTIONS="--max-old-space-size=4096"

# Project-specific helper
node scripts/get-memory.js   # Calculates optimal heap size based on available RAM
```

## ES Modules

This project uses ES modules (`"type": "module"` in `package.json`):

```javascript
// ✅ Correct
import { getPayload } from 'payload'
import config from './payload.config.js'

// ❌ Wrong (CommonJS)
const payload = require('payload')
```

Exception: PM2 ecosystem file uses `.cjs` extension (`ecosystem.config.cjs`) because PM2 requires CommonJS.

## Environment Variables

```bash
# Load from .env file (Node.js 24 supports --env-file natively)
node --env-file=shared/app.env src/server.js

# Or use dotenv in code
import 'dotenv/config'
```

## Debugging

```bash
# Inspect mode (attach Chrome DevTools)
node --inspect src/server.js

# Break on first line
node --inspect-brk src/server.js

# Verbose garbage collection logs
node --trace-gc src/server.js

# Diagnose memory leaks
node --heapsnapshot-signal=SIGUSR2 src/server.js
# Then: kill -USR2 <pid>
```

## Node.js 24 Key Features

- **Native `fetch()`**: No need for `node-fetch` package.
- **`--env-file`**: Native `.env` file loading without dotenv.
- **`URL.parse()`**: Safe URL parsing without try/catch.
- **`import.meta.dirname`**: Replaces `__dirname` in ESM.
- **`AbortSignal.any()`**: Combine multiple abort signals.
- **Stable `fs.glob()`**: Native glob support.
- **`structuredClone()`**: Deep clone without libraries.

## Common Diagnostics

```bash
# Check Node.js process resource usage
node -e "console.log(process.resourceUsage())"

# List loaded native modules
node -e "console.log(process.moduleLoadList.length, 'modules loaded')"

# Check OpenSSL version (for TLS/SSL)
node -e "console.log(process.versions.openssl)"

# Check V8 version
node -e "console.log(process.versions.v8)"
```

## Official Documentation
- Node.js 24: https://nodejs.org/docs/latest-v24.x/api/
- ES Modules: https://nodejs.org/docs/latest-v24.x/api/esm.html
- CLI Options: https://nodejs.org/docs/latest-v24.x/api/cli.html
- pnpm: https://pnpm.io/
- Corepack: https://nodejs.org/docs/latest-v24.x/api/corepack.html
