---
name: req-marketing-design
description: >-
  Design and implement Req marketing site (/) only — Innoventures-inspired dark
  premium palette, shadcn components in components/shadcn, Motion animations.
  Use with UI UX Pro Max for design intelligence. Do not change portal UI tokens.
---

# Req marketing design

## Scope

- **In scope:** `frontend/src/marketing/**`, `frontend/src/components/shadcn/**`, marketing tokens, [`MarketingLayout`](frontend/src/components/layout/MarketingLayout.tsx)
- **Out of scope:** `frontend/src/components/ui/**`, portal routes, app `tailwind` accent colors

## UI UX Pro Max (optional agent workflow)

Install globally in Cursor when refining design:

```
/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
/plugin install ui-ux-pro-max@ui-ux-pro-max-skill
```

Search example (adapt paths to your environment):

```
enterprise AI B2B workflow discovery dark premium government
```

Map results → [`frontend/src/marketing/marketing-tokens.ts`](frontend/src/marketing/marketing-tokens.ts) and [`frontend/tailwind.config.js`](frontend/tailwind.config.js) `marketing.*` colors.

## Token reference

| Token | Usage |
|-------|--------|
| `marketing-bg` | Page background `#050508` |
| `marketing-surface` | Cards `#111118` |
| `marketing-accent` | Cyan CTA/links `#22d3ee` |
| `marketing-gold` | Eyebrows, dividers `#d4a853` |
| `marketing-glass` | `bg-white/10 backdrop-blur border-white/20` |

## Component conventions

- Marketing buttons: `@/components/shadcn/button` (CVA variants)
- Portal buttons: `@/components/ui/Button` (unchanged)
- Animation: `motion/react` only — never add `framer-motion`
- Copy: [`frontend/src/marketing/content.ts`](frontend/src/marketing/content.ts)

## Pre-ship checklist

- [ ] Contrast ≥ 4.5:1 on body text over `marketing-bg`
- [ ] `useReducedMotion()` disables rotating hero and heavy shaders
- [ ] Hover/focus visible on all interactive elements
- [ ] No layout shift when rotating headline words change
- [ ] Stagger delays 0.05–0.10s; no gratuitous motion on portals
- [ ] `npm run build` passes in `frontend/`

## 21st.dev integration

Add blocks to `frontend/src/components/shadcn/` via shadcn CLI registry URLs. Always:

1. Replace `framer-motion` → `motion/react`
2. Wire copy from `content.ts`
3. Use `marketing-*` Tailwind classes inside `.marketing` wrapper
