/* ═══════════════════════════════════════════════════════════════
   SkillRoot — Tailwind Design Token System
   Premium 3D Silk Edition
   ═══════════════════════════════════════════════════════════════
   Palette: deep void → indigo → electric cyan → violet sheen
   Surface: heavy glassmorphism with neon glow accents
   Motion: 60fps float / pulse / shimmer / drift keyframes
   ═══════════════════════════════════════════════════════════════ */

import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      /* ── Silk Colour Palette ─────────────────────────────── */
      colors: {
        /* Void blacks — the deepest possible base */
        void: {
          DEFAULT: '#030014',
          50: '#0a0628',
          100: '#110b3a',
          200: '#1a1250',
          300: '#231a68',
        },
        /* Neon accents — the electric highlights */
        neon: {
          cyan: '#22d3ee',
          'cyan-bright': '#67e8f9',
          'cyan-dim': '#0e7490',
          violet: '#8b5cf6',
          'violet-bright': '#a78bfa',
          'violet-dim': '#6d28d9',
          indigo: '#6366f1',
        },
        /* Silk whites — text hierarchy */
        silk: {
          DEFAULT: '#f0f0ff',
          dim: '#a0a0c0',
          muted: '#6b6b8a',
          faint: '#3d3d5c',
        },
        /* Legacy compat — accent maps to neon cyan */
        accent: '#22d3ee',
      },

      /* ── Gradient Backgrounds ────────────────────────────── */
      backgroundImage: {
        /* Hero silk sweep: indigo → cyan → violet */
        'silk-gradient': 'linear-gradient(135deg, #1e1b4b 0%, #0e7490 50%, #7c3aed 100%)',
        /* Subtle top-down radial for section ambiance */
        'silk-radial': 'radial-gradient(ellipse at 50% 0%, rgba(139,92,246,0.15) 0%, transparent 60%)',
        /* Soft top glow for hero headers */
        'glow-top': 'radial-gradient(ellipse 80% 50% at 50% -20%, rgba(34,211,238,0.12) 0%, transparent 100%)',
        /* Center orb glow for cards */
        'glow-center': 'radial-gradient(circle at 50% 50%, rgba(139,92,246,0.08) 0%, transparent 50%)',
        /* Conic sweep for animated borders */
        'silk-conic': 'conic-gradient(from 180deg at 50% 50%, #1e1b4b, #06b6d4, #7c3aed, #1e1b4b)',
      },

      /* ── Glow Box Shadows ────────────────────────────────── */
      boxShadow: {
        'glow-xs': '0 0 8px -2px rgba(34, 211, 238, 0.2)',
        'glow-sm': '0 0 15px -3px rgba(34, 211, 238, 0.25)',
        'glow': '0 0 30px -5px rgba(34, 211, 238, 0.35)',
        'glow-lg': '0 0 60px -10px rgba(34, 211, 238, 0.4)',
        'glow-xl': '0 0 90px -15px rgba(34, 211, 238, 0.45)',
        'glow-violet-sm': '0 0 15px -3px rgba(139, 92, 246, 0.25)',
        'glow-violet': '0 0 30px -5px rgba(139, 92, 246, 0.35)',
        'glow-violet-lg': '0 0 60px -10px rgba(139, 92, 246, 0.4)',
        'glass': '0 8px 32px rgba(0, 0, 0, 0.37)',
        'glass-lg': '0 16px 64px rgba(0, 0, 0, 0.5)',
        'inner-glow': 'inset 0 1px 1px rgba(255, 255, 255, 0.06)',
      },

      /* ── Extended Blur ───────────────────────────────────── */
      backdropBlur: {
        '3xl': '64px',
        '4xl': '96px',
      },

      /* ── Typography ──────────────────────────────────────── */
      fontFamily: {
        sans: ['var(--font-inter)', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['var(--font-jetbrains)', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      fontSize: {
        '2xs': ['0.625rem', { lineHeight: '0.875rem' }],
        'display': ['3.5rem', { lineHeight: '1.1', letterSpacing: '-0.02em', fontWeight: '700' }],
        'display-sm': ['2.5rem', { lineHeight: '1.15', letterSpacing: '-0.015em', fontWeight: '700' }],
      },

      /* ── Border Radius ───────────────────────────────────── */
      borderRadius: {
        '4xl': '2rem',
      },

      /* ── Transitions ─────────────────────────────────────── */
      transitionTimingFunction: {
        silk: 'cubic-bezier(0.25, 0.46, 0.45, 0.94)',
        bounce: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
      },

      /* ── Animation Names ─────────────────────────────────── */
      animation: {
        'float': 'float 6s ease-in-out infinite',
        'float-slow': 'float 8s ease-in-out infinite',
        'float-delayed': 'float 7s ease-in-out 2s infinite',
        'pulse-glow': 'pulse-glow 4s ease-in-out infinite',
        'pulse-glow-fast': 'pulse-glow 2s ease-in-out infinite',
        'shimmer': 'shimmer 2.5s linear infinite',
        'spin-slow': 'spin 20s linear infinite',
        'drift': 'drift 25s ease-in-out infinite',
        'fade-in': 'fade-in 0.6s ease-out forwards',
        'fade-in-up': 'fade-in-up 0.8s ease-out forwards',
        'fade-in-down': 'fade-in-down 0.8s ease-out forwards',
        'scale-in': 'scale-in 0.4s ease-out forwards',
        'slide-in-right': 'slide-in-right 0.6s ease-out forwards',
      },

      /* ── Keyframes ───────────────────────────────────────── */
      keyframes: {
        /* Gentle vertical float — 3D depth illusion */
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-20px)' },
        },
        /* Breathing glow pulse */
        'pulse-glow': {
          '0%, 100%': { opacity: '0.4' },
          '50%': { opacity: '1' },
        },
        /* Horizontal gradient sweep — loading / emphasis */
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
        /* Organic wandering path for particles */
        drift: {
          '0%, 100%': { transform: 'translate(0, 0)' },
          '25%': { transform: 'translate(10px, -15px)' },
          '50%': { transform: 'translate(-5px, -25px)' },
          '75%': { transform: 'translate(-15px, -10px)' },
        },
        /* Entrance animations */
        'fade-in': {
          from: { opacity: '0' },
          to: { opacity: '1' },
        },
        'fade-in-up': {
          from: { opacity: '0', transform: 'translateY(24px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
        'fade-in-down': {
          from: { opacity: '0', transform: 'translateY(-24px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
        'scale-in': {
          from: { opacity: '0', transform: 'scale(0.92)' },
          to: { opacity: '1', transform: 'scale(1)' },
        },
        'slide-in-right': {
          from: { opacity: '0', transform: 'translateX(24px)' },
          to: { opacity: '1', transform: 'translateX(0)' },
        },
      },
    },
  },
  plugins: [],
};

export default config;
