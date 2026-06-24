/** @type {import('tailwindcss').Config} */
import tailwindcssAnimate from 'tailwindcss-animate';

export default {
  darkMode: ['class'],
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        border: {
          DEFAULT: 'hsl(var(--border))',
          strong: 'hsl(var(--border))',
        },
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--primary))',
          hover: 'hsl(239 84% 58%)',
          muted: 'hsl(239 84% 97%)',
          foreground: 'hsl(var(--accent-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
        success: {
          DEFAULT: 'hsl(var(--success))',
          foreground: 'hsl(var(--success-foreground))',
        },
        warning: {
          DEFAULT: 'hsl(var(--warning))',
          foreground: 'hsl(var(--warning-foreground))',
        },
        info: {
          DEFAULT: 'hsl(var(--info))',
          foreground: 'hsl(var(--info-foreground))',
        },
        chart: {
          1: 'hsl(var(--chart-1))',
          2: 'hsl(var(--chart-2))',
          3: 'hsl(var(--chart-3))',
          4: 'hsl(var(--chart-4))',
          5: 'hsl(var(--chart-5))',
          6: 'hsl(var(--chart-6))',
        },
        sidebar: {
          DEFAULT: 'hsl(var(--sidebar-background))',
          foreground: 'hsl(var(--sidebar-foreground))',
          primary: 'hsl(var(--sidebar-primary))',
          'primary-foreground': 'hsl(var(--sidebar-primary-foreground))',
          accent: 'hsl(var(--sidebar-accent))',
          'accent-foreground': 'hsl(var(--sidebar-accent-foreground))',
          border: 'hsl(var(--sidebar-border))',
          ring: 'hsl(var(--sidebar-ring))',
          hover: 'hsl(var(--muted))',
          active: 'hsl(var(--sidebar-accent))',
        },
        surface: {
          DEFAULT: 'hsl(var(--card))',
          muted: 'hsl(var(--background))',
        },
        text: {
          primary: 'hsl(var(--foreground))',
          secondary: 'hsl(var(--muted-foreground))',
          inverse: 'hsl(var(--primary-foreground))',
        },
        status: {
          success: 'hsl(var(--success))',
          successBg: 'hsl(160 84% 95%)',
          warning: 'hsl(var(--warning))',
          warningBg: 'hsl(38 92% 95%)',
          error: 'hsl(var(--destructive))',
          errorBg: 'hsl(0 84% 95%)',
          info: 'hsl(var(--info))',
          infoBg: 'hsl(217 91% 95%)',
          neutral: 'hsl(var(--muted-foreground))',
          neutralBg: 'hsl(var(--muted))',
        },
        marketing: {
          bg: 'hsl(var(--background))',
          surface: 'hsl(var(--card))',
          'surface-elevated': 'hsl(var(--muted))',
          foreground: 'hsl(var(--foreground))',
          muted: 'hsl(var(--muted-foreground))',
          accent: {
            DEFAULT: 'hsl(var(--primary))',
            hover: 'hsl(239 84% 58%)',
            muted: 'hsl(239 84% 97%)',
          },
          gold: '#d4a853',
          border: 'hsl(var(--border))',
        },
      },
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
        card: 'var(--radius)',
        button: 'calc(var(--radius) - 2px)',
        badge: '9999px',
        modal: 'var(--radius)',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        display: ['Inter', 'system-ui', 'sans-serif'],
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
      boxShadow: {
        card: '0 1px 2px 0 rgb(0 0 0 / 0.04)',
        modal: '0 20px 25px -5px rgb(0 0 0 / 0.1)',
        'hero-mockup': '0 1px 3px 0 rgb(0 0 0 / 0.08), 0 8px 24px rgb(0 0 0 / 0.06)',
        'button-glow': '0 0 20px hsl(var(--primary) / 0.3)',
        'marketing-glow': '0 0 40px hsl(var(--primary) / 0.15)',
        'marketing-card': '0 1px 3px 0 rgb(0 0 0 / 0.06), 0 8px 24px rgb(0 0 0 / 0.04)',
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
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
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
        'accordion-down': {
          from: { height: '0' },
          to: { height: 'var(--radix-accordion-content-height)' },
        },
        'accordion-up': {
          from: { height: 'var(--radix-accordion-content-height)' },
          to: { height: '0' },
        },
      },
    },
  },
  plugins: [tailwindcssAnimate],
};
