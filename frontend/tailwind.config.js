/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        sidebar: { DEFAULT: '#0F1117', hover: '#1A1D27', active: '#22263A' },
        surface: { DEFAULT: '#FFFFFF', muted: '#F8F9FC' },
        border: { DEFAULT: '#E5E7EB', strong: '#D1D5DB' },
        accent: { DEFAULT: '#4F46E5', hover: '#4338CA', muted: '#EEF2FF' },
        text: { primary: '#111827', secondary: '#6B7280', inverse: '#F9FAFB' },
        status: {
          success: '#10B981',
          successBg: '#D1FAE5',
          warning: '#F59E0B',
          warningBg: '#FEF3C7',
          error: '#EF4444',
          errorBg: '#FEE2E2',
          info: '#3B82F6',
          infoBg: '#DBEAFE',
          neutral: '#6B7280',
          neutralBg: '#F3F4F6',
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
        card: '0 1px 2px 0 rgb(0 0 0 / 0.04)',
        modal: '0 20px 25px -5px rgb(0 0 0 / 0.1)',
        'hero-mockup':
          '0 0 0 1px rgba(255,255,255,0.05), 0 25px 50px rgba(0,0,0,0.5)',
        'button-glow': '0 0 20px rgba(79,70,229,0.4)',
      },
      animation: {
        'grid-drift': 'gridDrift 60s linear infinite',
        'cta-pulse': 'ctaPulse 3s ease-out infinite',
        'cta-pulse-delayed': 'ctaPulse 3s ease-out 1.5s infinite',
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
      },
    },
  },
  plugins: [],
};
