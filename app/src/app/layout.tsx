/* ═══════════════════════════════════════════════════════════════
   File: src/app/layout.tsx
   SkillRoot — Root Layout
   ═══════════════════════════════════════════════════════════════
   Sets up Inter + JetBrains Mono via next/font, injects CSS
   custom-property font vars for Tailwind, wraps the app in
   Providers, and renders ambient background through globals.css.
   ═══════════════════════════════════════════════════════════════ */

import './globals.css';
import '@rainbow-me/rainbowkit/styles.css';
import type { Metadata } from 'next';
import { Inter, JetBrains_Mono } from 'next/font/google';
import { Providers } from './providers';

/* ── Font Loading ────────────────────────────────────────────── */
const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-inter',
});

const jetbrains = JetBrains_Mono({
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-jetbrains',
});

/* ── Metadata ────────────────────────────────────────────────── */
export const metadata: Metadata = {
  title: 'SkillRoot — Decentralized Skill Attestation',
  description:
    'The Bitcoin-level primitive for human capability signaling. Prove knowledge with zero-knowledge proofs, verified by stake-weighted committees, recorded permanently on-chain.',
  keywords: ['zkp', 'attestation', 'skill', 'decentralized', 'on-chain', 'groth16'],
  icons: {
    icon: [
      { url: '/favicon.ico', sizes: '32x32' },
      { url: '/favicon.svg', type: 'image/svg+xml' },
    ],
    apple: '/favicon.svg',
  },
  openGraph: {
    title: 'SkillRoot',
    description: 'Decentralized skill attestation protocol.',
    type: 'website',
  },
};

/* ── Root Layout ─────────────────────────────────────────────── */
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${jetbrains.variable}`}>
      <body className="font-sans antialiased">
        <Providers>
          {/*
            Main content container — sits above the ambient
            body::before / body::after layers defined in globals.css.
            Max-width 72rem (1152px) keeps content readable on
            ultrawide displays while feeling spacious on 1440p.
          */}
          <main className="relative z-10 min-h-screen w-full max-w-6xl mx-auto px-5 sm:px-8 py-8 sm:py-12">
            {children}
          </main>
        </Providers>
      </body>
    </html>
  );
}
