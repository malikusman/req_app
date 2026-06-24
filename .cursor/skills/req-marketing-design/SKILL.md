---
name: req-marketing-design
description: >-
  Design and implement Req marketing site (/) only — unified light shadcn-based
  palette, shadcn components in components/shadcn, Motion animations.
  Use with UI UX Pro Max for design intelligence. Align with portal design tokens.
---

# Req marketing design

## Scope

- **In scope:** `frontend/src/marketing/**`, `frontend/src/components/shadcn/**`, marketing tokens, [`MarketingLayout`](frontend/src/components/layout/MarketingLayout.tsx)
- **Out of scope:** portal route logic, backend APIs

## Unified design system

Marketing and portals share the same light shadcn token layer:

- CSS variables in [`frontend/src/index.css`](frontend/src/index.css) (`:root`)
- Tailwind mappings in [`frontend/tailwind.config.js`](frontend/tailwind.config.js)
- shadcn primitives in [`frontend/src/components/shadcn/`](frontend/src/components/shadcn/)
- Portal wrappers in [`frontend/src/components/ui/`](frontend/src/components/ui/) (same API, shadcn internals)

## UI UX Pro Max (optional agent workflow)

Install globally in Cursor when refining design:

```
/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
/plugin install ui-ux-pro-max@ui-ux-pro-max-skill
```

Search example (adapt paths to your environment):

```
enterprise AI B2B workflow discovery light premium government
```

Map results → [`frontend/src/marketing/marketing-tokens.ts`](frontend/src/marketing/marketing-tokens.ts) and `marketing.*` colors in tailwind config.

## Token reference

| Token | Usage |
|-------|--------|
| `marketing-bg` | Page background (light slate) |
| `marketing-surface` | Cards (white) |
| `marketing-accent` | Indigo CTA/links (matches `--primary`) |
| `marketing-gold` | Eyebrows, dividers |
| `background`, `foreground`, `primary` | shadcn CSS vars — prefer for new work |

## Component conventions

- Marketing buttons: `@/components/shadcn/button` (CVA variants)
- Portal buttons: `@/components/ui/Button` (wraps shadcn)
- FAQ: shadcn `Accordion`
- Animation: `motion/react` only — never add `framer-motion`
- Copy: [`frontend/src/marketing/content.ts`](frontend/src/marketing/content.ts)
- Typography: Inter only; tabular nums for metrics

## Pre-ship checklist

- [ ] Contrast ≥ 4.5:1 on body text over light backgrounds
- [ ] `useReducedMotion()` disables rotating hero and heavy shaders
- [ ] Hover/focus visible on all interactive elements
- [ ] No layout shift when rotating headline words change
- [ ] Stagger delays 0.05–0.10s; no gratuitous motion on portals
- [ ] `npm run build` passes in `frontend/`

## 21st.dev integration

Add blocks to `frontend/src/components/shadcn/` via shadcn CLI registry URLs. Always:

1. Replace `framer-motion` → `motion/react`
2. Wire copy from `content.ts`
3. Use `marketing-*` or shadcn token classes inside `.marketing` wrapper
