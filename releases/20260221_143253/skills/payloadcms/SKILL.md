---
name: PayloadCMS Development
description: How to develop with PayloadCMS 3.x — collections, globals, hooks, access control, plugins, migrations, and REST/Local API usage.
---

# PayloadCMS Development Skill

## Overview

PayloadCMS 3.x is a headless CMS that runs on top of Next.js. In this project, Payload serves as the **backend-only** content API (`/admin`, `/api`), while Astro handles the frontend.

## Key Concepts

### Collections
- Define content types in `payloadcms/src/collections/`.
- Each collection = a database table + REST API endpoint + Admin UI.
- Always specify `slug` (kebab-case), `labels`, `admin.useAsTitle`, and `access` control.
- Enable `versions.drafts: true` for content that needs editorial workflow.

### Globals
- Define singleton data (site settings, header, footer) in `payloadcms/src/globals/`.
- Globals are accessed via `/api/globals/{slug}`.
- Always add cache tags for ISR revalidation.

### Access Control
- **Never use `() => true` for read access in production.** Always specify proper access functions.
- Role hierarchy: `admin` > `editor` > `author` > `viewer`.
- Access functions receive `{ req }` with `req.user` containing the authenticated user.
- Common patterns:
  ```typescript
  // Authenticated users only
  read: ({ req }) => !!req.user
  
  // Admin only
  create: ({ req }) => req.user?.roles?.includes('admin')
  
  // Published content is public, drafts require auth
  read: ({ req }) => {
    if (req.user) return true
    return { _status: { equals: 'published' } }
  }
  ```

### Hooks
- `beforeValidate`, `beforeChange`, `afterChange`, `beforeDelete`, `afterDelete`.
- Use `afterChange` to trigger external actions (webhooks, cache invalidation).
- Hooks run server-side and have full access to `req.payload` (Local API).
- Example: Trigger Astro rebuild after content publish:
  ```typescript
  afterChange: [
    async ({ doc, operation }) => {
      if (operation === 'update' && doc._status === 'published') {
        await fetch(process.env.REBUILD_WEBHOOK_URL, { method: 'POST' })
      }
    }
  ]
  ```

### Plugins
- **SEO**: `@payloadcms/plugin-seo` — adds `meta.title`, `meta.description`, `meta.image` fields.
- **Cloud Storage**: `@payloadcms/plugin-cloud-storage` — S3/R2/RustFS media uploads.
- **Nested Docs**: `@payloadcms/plugin-nested-docs` — hierarchical pages with breadcrumbs.
- Configure plugins in `payloadcms/src/payload.config.ts`.

### Migrations
- **Always use `push: false`** in production database adapter config.
- Workflow:
  1. Make schema changes in collection/global files.
  2. `pnpm --dir payloadcms payload migrate:create <name>`.
  3. Review generated SQL migration file.
  4. `pnpm --dir payloadcms payload migrate`.
  5. Verify with `pnpm --dir payloadcms payload migrate:status`.
- If `migrate:create` hangs (interactive prompt), create migration SQL manually.

### Data Fetching (from Astro)
Two approaches:

1. **REST API via `@payloadcms/sdk`** (recommended for separate deployments):
   ```typescript
   import { PayloadSDK } from '@payloadcms/sdk'
   const sdk = new PayloadSDK({ apiURL: 'https://cms.example.com/api' })
   const posts = await sdk.find({ collection: 'posts', limit: 10 })
   ```

2. **Local API** (if Astro and Payload share Node.js process):
   ```typescript
   import { getPayload } from 'payload'
   import config from '../payloadcms/payload.config'
   const payload = await getPayload({ config })
   const posts = await payload.find({ collection: 'posts' })
   ```

### Live Preview
- Payload provides Live Preview via iframe + `window.postMessage`.
- Official hooks exist for React and Vue only.
- For Astro: use `@payloadcms/live-preview` low-level API (`subscribe`, `unsubscribe`, `ready`).
- Configure in `payload.config.ts`:
  ```typescript
  admin: {
    livePreview: {
      url: ({ data, locale }) =>
        `${process.env.ASTRO_PREVIEW_URL}/preview/${locale.code}/${data.slug}`,
      collections: ['pages', 'posts'],
      breakpoints: [
        { label: 'Mobile', width: 375, height: 667 },
        { label: 'Desktop', width: 1440, height: 900 },
      ],
    },
  }
  ```

## Common Commands

```bash
# Development
pnpm --dir payloadcms dev

# Build
pnpm --dir payloadcms build

# Generate types
pnpm --dir payloadcms payload generate:types

# Run migrations
pnpm --dir payloadcms payload migrate

# Create migration
pnpm --dir payloadcms payload migrate:create <name>

# Seed data
pnpm --dir payloadcms payload run src/seed.ts
```

## Official Documentation
- Getting Started: https://payloadcms.com/docs/getting-started/what-is-payload
- Collections: https://payloadcms.com/docs/configuration/collections
- Globals: https://payloadcms.com/docs/configuration/globals
- Access Control: https://payloadcms.com/docs/access-control/overview
- Hooks: https://payloadcms.com/docs/hooks/overview
- REST API: https://payloadcms.com/docs/rest-api/overview
- Live Preview: https://payloadcms.com/docs/live-preview/overview
- Migrations: https://payloadcms.com/docs/database/migrations
