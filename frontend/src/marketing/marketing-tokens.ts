/**
 * Pulse marketing palette — aligned with unified shadcn design tokens.
 * Scoped to `.marketing` wrapper; maps to `marketing.*` in tailwind.config.js.
 */
export const marketingTokens = {
  background: 'hsl(135 29% 97%)',
  surface: 'hsl(0 0% 100%)',
  surfaceElevated: 'hsl(143 27% 94%)',
  foreground: 'hsl(146 23% 12%)',
  muted: 'hsl(144 8% 39%)',
  accent: 'hsl(160 84% 34%)',
  accentHover: 'hsl(160 83% 26%)',
  gold: '#d4a853',
  border: 'hsl(138 21% 91%)',
  glow: 'hsl(160 84% 34% / 0.15)',
} as const;
