---
name: Astro Development
description: How to develop with Astro 5.x — static site generation, Islands architecture, content collections, i18n, image pipeline, and integration with headless CMS.
---

# Astro Development Skill

## Overview

Astro is a static-first web framework. In this project, Astro generates the public-facing frontend as static HTML served by Nginx. Dynamic features use Islands architecture (client-side hydration only where needed).

## Core Concepts

### Output Modes
- **`output: "static"`** (default, this project): All pages pre-rendered at build time.
- **`output: "server"`**: All pages rendered on-demand (SSR).
- **`output: "static"` + per-route `export const prerender = false`**: Hybrid mode. Most pages static, specific routes SSR.

This project uses **hybrid mode**: static for all public pages, SSR only for the `/preview/` Live Preview route.

### File-Based Routing
- Pages live in `astro-frontend/src/pages/`.
- `[slug].astro` = dynamic route.
- `[...path].astro` = catch-all route.
- `[lang]/[...path].astro` = i18n dynamic route.

### Static Path Generation
For static output, dynamic routes require `getStaticPaths()`:
```astro
---
// src/pages/posts/[slug].astro
export async function getStaticPaths() {
  const posts = await sdk.find({ collection: 'posts', limit: 0 })
  return posts.docs.map(post => ({
    params: { slug: post.slug },
    props: { post },
  }))
}
const { post } = Astro.props
---
<h1>{post.title}</h1>
```

### Islands Architecture
- Astro components are **server-only by default** (zero JS shipped).
- Use `client:*` directives to hydrate interactive components:
  - `client:load` — Hydrate immediately (above-fold interactive elements).
  - `client:visible` — Hydrate when visible in viewport (lazy).
  - `client:idle` — Hydrate when browser is idle (non-critical).
  - `client:media="(max-width: 768px)"` — Hydrate on media query match.
  - `client:only="react"` — Client-only, skip SSR entirely.
- Example:
  ```astro
  <SearchWidget client:idle />
  <MobileMenu client:media="(max-width: 768px)" />
  ```

### Content Collections
For non-CMS static content (legal pages, documentation):
```typescript
// src/content.config.ts
import { defineCollection, z } from 'astro:content'

const docs = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    date: z.date(),
  }),
})

export const collections = { docs }
```

### Image Pipeline (`astro:assets`)
```astro
---
import { Image } from 'astro:assets'
---
<Image
  src={post.heroImage.url}
  alt={post.heroImage.alt}
  width={1200}
  height={630}
  format="webp"
/>
```
- Configure allowed remote image domains in `astro.config.mjs`:
  ```javascript
  image: {
    domains: ['cms.example.com', 's3.example.com'],
  }
  ```

### i18n (Built-in)
```javascript
// astro.config.mjs
export default defineConfig({
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'zh', 'ja'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
})
```
- Use `Astro.currentLocale` in components.
- Use `getRelativeLocaleUrl()` for locale-aware links.

### View Transitions
```astro
---
import { ViewTransitions } from 'astro:transitions'
---
<head>
  <ViewTransitions />
</head>
```
- Add `transition:name` for element-level animations.
- Add `transition:animate="slide"` for page-level transitions.

### Environment Variables (`astro:env`)
```javascript
// astro.config.mjs
import { defineConfig, envField } from 'astro/config'

export default defineConfig({
  env: {
    schema: {
      PUBLIC_SITE_URL: envField.string({ context: 'client', access: 'public' }),
      PUBLIC_API_BASE_URL: envField.string({ context: 'client', access: 'public' }),
      PAYLOAD_API_KEY: envField.string({ context: 'server', access: 'secret' }),
    },
  },
})
```

### Integrations
Common integrations for this project:
```javascript
// astro.config.mjs
import tailwind from '@astrojs/tailwind'
import sitemap from '@astrojs/sitemap'
import node from '@astrojs/node'

export default defineConfig({
  site: 'https://example.com',
  integrations: [tailwind(), sitemap()],
  adapter: node({ mode: 'standalone' }), // Only for preview SSR route
})
```

## Astro Component Patterns

### Layout Pattern
```astro
---
// src/layouts/Layout.astro
const { title, description } = Astro.props
---
<html lang={Astro.currentLocale}>
<head>
  <meta charset="utf-8" />
  <title>{title}</title>
  <meta name="description" content={description} />
  <ViewTransitions />
</head>
<body>
  <Header />
  <slot />
  <Footer />
</body>
</html>
```

### Data Fetching in Pages
```astro
---
// src/pages/index.astro
import Layout from '../layouts/Layout.astro'
import { sdk } from '../lib/cms'

const homepage = await sdk.findGlobal({ slug: 'home-settings' })
const posts = await sdk.find({ collection: 'posts', limit: 6, sort: '-publishedDate' })
---
<Layout title={homepage.hero.title}>
  <Hero data={homepage.hero} />
  {posts.docs.map(post => <PostCard post={post} />)}
</Layout>
```

## Common Commands

```bash
# Development
pnpm --dir astro-frontend dev

# Build (static output)
pnpm --dir astro-frontend build

# Preview built site
pnpm --dir astro-frontend preview

# Check types
pnpm --dir astro-frontend astro check
```

## Official Documentation
- Getting Started: https://docs.astro.build/en/getting-started/
- Rendering Modes: https://docs.astro.build/en/basics/rendering-modes/
- Islands: https://docs.astro.build/en/concepts/islands/
- Content Collections: https://docs.astro.build/en/guides/content-collections/
- Images: https://docs.astro.build/en/guides/images/
- i18n: https://docs.astro.build/en/guides/internationalization/
- View Transitions: https://docs.astro.build/en/guides/view-transitions/
- CMS Integration (Payload): https://docs.astro.build/en/guides/cms/payload/
