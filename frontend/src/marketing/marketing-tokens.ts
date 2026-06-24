/**
 * Light marketing palette — aligned with unified shadcn design tokens.
 * Scoped to `.marketing` wrapper; maps to `marketing.*` in tailwind.config.js.
 */
export const marketingTokens = {
  background: 'hsl(210 40% 98%)',
  surface: 'hsl(0 0% 100%)',
  surfaceElevated: 'hsl(210 40% 96%)',
  foreground: 'hsl(222 47% 11%)',
  muted: 'hsl(215 16% 47%)',
  accent: 'hsl(239 84% 67%)',
  accentHover: 'hsl(239 84% 58%)',
  gold: '#d4a853',
  border: 'hsl(214 32% 91%)',
  glow: 'hsl(239 84% 67% / 0.15)',
} as const;
