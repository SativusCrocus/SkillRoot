/* ═══════════════════════════════════════════════════════════════
   ConnectButton — 3D Glass Wallet Connector
   ═══════════════════════════════════════════════════════════════
   Custom RainbowKit render with glass surfaces, neon glow sweep
   on hover, chain indicator pill, and status dot for connected
   state. Uses RKConnectButton.Custom for full rendering control.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import { ConnectButton as RKConnectButton } from '@rainbow-me/rainbowkit';

export function ConnectButton() {
  return (
    <RKConnectButton.Custom>
      {({
        account,
        chain,
        openAccountModal,
        openChainModal,
        openConnectModal,
        authenticationStatus,
        mounted,
      }) => {
        const ready = mounted && authenticationStatus !== 'loading';
        const connected =
          ready &&
          account &&
          chain &&
          (!authenticationStatus || authenticationStatus === 'authenticated');

        return (
          <div
            {...(!ready && {
              'aria-hidden': true,
              style: {
                opacity: 0,
                pointerEvents: 'none' as const,
                userSelect: 'none' as const,
              },
            })}
          >
            {(() => {
              if (!connected) {
                return (
                  <button
                    onClick={openConnectModal}
                    className="btn-silk group relative overflow-hidden"
                  >
                    <span className="relative z-10">Connect Wallet</span>
                    {/* Glow sweep on hover */}
                    <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/[0.06] to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-700 ease-out" />
                  </button>
                );
              }

              if (chain.unsupported) {
                return (
                  <button
                    onClick={openChainModal}
                    className="btn-silk border-red-500/30 text-red-400 hover:border-red-500/50"
                  >
                    Wrong Network
                  </button>
                );
              }

              return (
                <div className="flex items-center gap-2">
                  {/* Chain indicator pill */}
                  <button
                    onClick={openChainModal}
                    className="glass-subtle px-3 py-2 text-xs font-medium text-silk-dim hover:text-silk hover:border-white/[0.12] transition-all duration-200 flex items-center gap-1.5"
                  >
                    {chain.hasIcon && chain.iconUrl && (
                      <img
                        alt={chain.name ?? 'Chain'}
                        src={chain.iconUrl}
                        className="w-3.5 h-3.5 rounded-full"
                      />
                    )}
                    <span className="hidden sm:inline">{chain.name}</span>
                  </button>

                  {/* Account button with status dot + glow sweep */}
                  <button
                    onClick={openAccountModal}
                    className="btn-silk text-sm font-mono group relative overflow-hidden"
                  >
                    <span className="relative z-10 flex items-center gap-2">
                      <span className="w-2 h-2 rounded-full bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.5)]" />
                      {account.displayName}
                    </span>
                    <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/[0.04] to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-700 ease-out" />
                  </button>
                </div>
              );
            })()}
          </div>
        );
      }}
    </RKConnectButton.Custom>
  );
}
