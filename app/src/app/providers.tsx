/* ═══════════════════════════════════════════════════════════════
   File: src/app/providers.tsx
   SkillRoot — Client Providers
   ═══════════════════════════════════════════════════════════════
   Wagmi + RainbowKit + React Query, with RainbowKit themed to
   match the void/silk design system. All accent colours pulled
   from the neon-cyan / void palette so the connect modal feels
   native to the 3D silk aesthetic.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import { WagmiProvider } from 'wagmi';
import { RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { wagmiConfig } from '@/lib/wagmi';
import { useState } from 'react';

/* ── Custom RainbowKit Theme ─────────────────────────────────── */
const silkTheme = darkTheme({
  accentColor: '#22d3ee',           /* neon-cyan — primary action */
  accentColorForeground: '#030014', /* void — text on accent */
  borderRadius: 'medium',
  fontStack: 'system',
  overlayBlur: 'large',
});

/* Override deeper tokens for full silk integration */
const skillRootTheme = {
  ...silkTheme,
  colors: {
    ...silkTheme.colors,
    modalBackground: 'rgba(3, 0, 20, 0.92)',       /* void with 92% opacity */
    modalBackdrop: 'rgba(3, 0, 20, 0.60)',          /* dim void overlay */
    modalBorder: 'rgba(255, 255, 255, 0.08)',       /* glass-border */
    profileForeground: 'rgba(10, 6, 40, 0.95)',     /* void-50 */
    connectButtonBackground: 'rgba(255, 255, 255, 0.03)', /* glass-bg */
    connectButtonInnerBackground: 'rgba(255, 255, 255, 0.06)',
    generalBorder: 'rgba(255, 255, 255, 0.08)',
    generalBorderDim: 'rgba(255, 255, 255, 0.05)',
  },
  shadows: {
    ...silkTheme.shadows,
    connectButton: '0 0 20px -4px rgba(34, 211, 238, 0.15)',
    dialog: '0 16px 64px rgba(0, 0, 0, 0.5)',
  },
};

/* ── Provider Tree ───────────────────────────────────────────── */
export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={skillRootTheme}>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
