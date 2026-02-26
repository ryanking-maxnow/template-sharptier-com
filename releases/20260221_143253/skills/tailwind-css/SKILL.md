---
name: Tailwind CSS v4
description: How to use Tailwind CSS v4 with its new CSS-first configuration, theme system, and modern utility patterns.
---

# Tailwind CSS v4 Skill

## Overview

Tailwind CSS v4 is a utility-first CSS framework. v4 introduces a major shift: **CSS-first configuration** replaces the old `tailwind.config.js`.

## Key Changes in v4

### CSS-First Configuration
No more `tailwind.config.js`. All configuration is in your CSS file:

```css
/* src/styles/global.css */
@import "tailwindcss";

@theme {
  --color-primary: oklch(0.6 0.2 250);
  --color-secondary: oklch(0.7 0.15 180);
  --font-sans: 'Inter', sans-serif;
  --font-heading: 'Outfit', sans-serif;
  --breakpoint-xs: 480px;
}
```

### New Features
- **Container queries**: `@container` utilities built-in.
- **`@starting-style`**: Animation entry states.
- **Anchor positioning**: CSS anchor positioning utilities.
- **Field sizing**: `field-size-content` for auto-sizing inputs.
- **Color mixing**: `bg-red-500/50` for opacity, `color-mix()` for blending.

### Dark Mode
```css
@variant dark (&:where(.dark, .dark *));
```
Or use the built-in `dark:` variant with `prefers-color-scheme`.

### Custom Variants
```css
@custom-variant theme-blue (&:where([data-theme="blue"] *));
```
Usage: `theme-blue:bg-blue-500`

## Common Patterns

### Responsive Design
```html
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
  <!-- Cards -->
</div>
```

### Glassmorphism
```html
<div class="bg-white/10 backdrop-blur-xl border border-white/20 rounded-2xl shadow-2xl">
  <!-- Content -->
</div>
```

### Gradients
```html
<div class="bg-gradient-to-br from-indigo-600 via-purple-500 to-pink-400">
  <!-- Content -->
</div>
```

### Animations
```html
<button class="transition-all duration-300 ease-out hover:scale-105 hover:shadow-lg active:scale-95">
  Click me
</button>
```

### Typography
```html
<h1 class="text-4xl md:text-6xl font-bold tracking-tight bg-gradient-to-r from-indigo-600 to-purple-500 bg-clip-text text-transparent">
  Heading
</h1>
```

## Integrating with Astro

```javascript
// astro.config.mjs
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  vite: {
    plugins: [tailwindcss()],
  },
})
```

```css
/* src/styles/global.css */
@import "tailwindcss";
```

```astro
---
// src/layouts/Layout.astro
import '../styles/global.css'
---
```

## Official Documentation
- Installation: https://tailwindcss.com/docs/installation/using-vite
- Theme Configuration: https://tailwindcss.com/docs/theme
- Upgrade Guide (v3→v4): https://tailwindcss.com/docs/upgrade-guide
