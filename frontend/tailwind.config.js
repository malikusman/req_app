/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        marketing: {
          bg: '#050508',
          surface: '#111118',
          'surface-elevated': '#16161f',
          foreground: '#f4f4f5',
          muted: '#a1a1aa',
          accent: { DEFAULT: '#22d3ee', hover: '#06b6d4', muted: 'rgba(34, 211, 238, 0.12)' },
          gold: '#d4a853',
          border: 'rgba(255, 255, 255, 0.08)',
        },
        sidebar: { DEFAULT: '#0B0D13', hover: '#161A24', active: '#1D2332' },
        surface: { DEFAULT: '#111118', muted: '#090B10' },
        border: { DEFAULT: 'rgba(255, 255, 255, 0.10)', strong: 'rgba(255, 255, 255, 0.16)' },
        accent: { DEFAULT: '#22d3ee', hover: '#06b6d4', muted: 'rgba(34, 211, 238, 0.14)' },
        text: { primary: '#f4f4f5', secondary: '#a1a1aa', inverse: '#f9fafb' },
        status: {
          success: '#34d399',
          successBg: 'rgba(52, 211, 153, 0.16)',
          warning: '#fbbf24',
          warningBg: 'rgba(251, 191, 36, 0.16)',
          error: '#f87171',
          errorBg: 'rgba(248, 113, 113, 0.16)',
          info: '#60a5fa',
          infoBg: 'rgba(96, 165, 250, 0.16)',
          neutral: '#cbd5e1',
          neutralBg: 'rgba(148, 163, 184, 0.16)',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        display: ['Sora', 'Inter', 'sans-serif'],
      },
      fontSize: {
        'page-title': ['1.5rem', { lineHeight: '2rem', fontWeight: '600' }],
        'section-title': ['1.125rem', { lineHeight: '1.75rem', fontWeight: '600' }],
        'label-caps': ['0.6875rem', { lineHeight: '1rem', fontWeight: '600', letterSpacing: '0.05em' }],
      },
      spacing: {
        sidebar: '240px',
        topbar: '60px',
        content: '32px',
      },
      maxWidth: {
        content: '1280px',
      },
      borderRadius: {
        card: '8px',
        button: '6px',
        badge: '9999px',
        modal: '12px',
      },
      boxShadow: {
        card: '0 0 0 1px rgba(255,255,255,0.06), 0 14px 40px rgba(0,0,0,0.32)',
        modal: '0 20px 25px -5px rgb(0 0 0 / 0.1)',
        'hero-mockup':
          '0 0 0 1px rgba(255,255,255,0.05), 0 25px 50px rgba(0,0,0,0.5)',
        'button-glow': '0 0 20px rgba(79,70,229,0.4)',
        'marketing-glow': '0 0 40px rgba(34, 211, 238, 0.25)',
        'marketing-card': '0 0 0 1px rgba(255,255,255,0.06), 0 12px 40px rgba(0,0,0,0.4)',
      },
      animation: {
        'grid-drift': 'gridDrift 60s linear infinite',
        'cta-pulse': 'ctaPulse 3s ease-out infinite',
        'cta-pulse-delayed': 'ctaPulse 3s ease-out 1.5s infinite',
        marquee: 'marquee 40s linear infinite',
        'border-beam-spin': 'borderBeamSpin 12s linear infinite',
        'border-beam-pulse': 'borderBeamPulse 4s ease-in-out infinite alternate',
        'text-gradient': 'textGradient 4s ease infinite',
        shine: 'shine 3s linear infinite',
      },
      keyframes: {
        gridDrift: {
          '0%': { backgroundPosition: '0 0' },
          '100%': { backgroundPosition: '64px 64px' },
        },
        ctaPulse: {
          '0%': { transform: 'scale(1)', opacity: '0.35' },
          '100%': { transform: 'scale(2.2)', opacity: '0' },
        },
        marquee: {
          '0%': { transform: 'translateX(0)' },
          '100%': { transform: 'translateX(-50%)' },
        },
        borderBeamSpin: {
          '0%': { transform: 'rotate(0deg)' },
          '100%': { transform: 'rotate(360deg)' },
        },
        borderBeamPulse: {
          '0%': { opacity: '0.4', transform: 'scale(0.95)' },
          '100%': { opacity: '0.7', transform: 'scale(1.05)' },
        },
        textGradient: {
          '0%, 100%': { backgroundPosition: '0% center' },
          '50%': { backgroundPosition: '100% center' },
        },
        shine: {
          '0%': { transform: 'rotate(0deg)' },
          '100%': { transform: 'rotate(360deg)' },
        },
      },
    },
  },
  plugins: [],
};
