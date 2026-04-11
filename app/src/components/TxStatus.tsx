/* ═══════════════════════════════════════════════════════════════
   TxStatus — Transaction Status with Particle Feedback
   ═══════════════════════════════════════════════════════════════
   Glass-panel transaction tracker with three visual states:
   pending (spinning ring), success (particle burst), error
   (red accent). Framer Motion AnimatePresence for smooth
   transitions between states.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useWaitForTransactionReceipt } from 'wagmi';
import type { Hash } from 'viem';

/* ── Deterministic particles for success burst ──────────────── */
function seededRandom(seed: number) {
  const x = Math.sin(seed * 9301 + 49297) * 49297;
  return x - Math.floor(x);
}

const SUCCESS_PARTICLES = Array.from({ length: 12 }, (_, i) => ({
  id: i,
  angle: (i / 12) * 360,
  distance: 30 + seededRandom(i) * 30,
  size: 2 + seededRandom(i + 50) * 3,
  delay: seededRandom(i + 100) * 0.3,
}));

/* ═══════════════════════════════════════════════════════════════ */
export function TxStatus({ hash }: { hash?: Hash }) {
  const { data, isLoading, isSuccess, isError, error } =
    useWaitForTransactionReceipt({ hash });
  const [showParticles, setShowParticles] = useState(false);

  useEffect(() => {
    if (isSuccess) {
      setShowParticles(true);
      const timer = setTimeout(() => setShowParticles(false), 2000);
      return () => clearTimeout(timer);
    }
  }, [isSuccess]);

  if (!hash) return null;

  return (
    <div className="glass-card p-5 sm:p-6 space-y-4 relative overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-3">
        <h3 className="text-xs font-semibold text-silk-muted uppercase tracking-wider">
          Transaction
        </h3>
        <hr className="neon-divider flex-1" />
      </div>

      {/* Hash display */}
      <div className="glass-subtle p-3 space-y-1">
        <div className="text-xs text-silk-muted">Hash</div>
        <code className="text-xs text-neon-cyan font-mono break-all">
          {hash}
        </code>
      </div>

      {/* Status — animated transitions between states */}
      <AnimatePresence mode="wait">
        {isLoading && (
          <motion.div
            key="loading"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            className="flex items-center gap-3 p-3 glass-subtle"
          >
            <div className="w-5 h-5 border-2 border-neon-cyan/30 border-t-neon-cyan rounded-full animate-spin" />
            <span className="text-sm text-silk-dim">Waiting for confirmation&hellip;</span>
          </motion.div>
        )}

        {isSuccess && (
          <motion.div
            key="success"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            className="relative"
          >
            <div className="flex items-center gap-3 p-3 glass-subtle border-emerald-500/20 border">
              <div className="relative">
                <span className="status-dot-success" />
                {/* Particle burst on success */}
                <AnimatePresence>
                  {showParticles && SUCCESS_PARTICLES.map((p) => {
                    const rad = (p.angle * Math.PI) / 180;
                    return (
                      <motion.div
                        key={p.id}
                        className="absolute top-1/2 left-1/2 rounded-full bg-emerald-400"
                        style={{ width: p.size, height: p.size }}
                        initial={{ x: 0, y: 0, opacity: 1, scale: 1 }}
                        animate={{
                          x: Math.cos(rad) * p.distance,
                          y: Math.sin(rad) * p.distance,
                          opacity: 0,
                          scale: 0,
                        }}
                        transition={{
                          duration: 0.8,
                          delay: p.delay,
                          ease: 'easeOut',
                        }}
                      />
                    );
                  })}
                </AnimatePresence>
              </div>
              <div className="space-y-0.5">
                <span className="text-sm text-emerald-400 font-medium">Confirmed</span>
                {data?.blockNumber && (
                  <div className="text-xs text-silk-faint font-mono">
                    Block #{String(data.blockNumber)}
                  </div>
                )}
              </div>
            </div>
          </motion.div>
        )}

        {isError && (
          <motion.div
            key="error"
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            className="flex items-start gap-3 p-3 glass-subtle border-red-500/20 border"
          >
            <span className="status-dot-error mt-0.5 shrink-0" />
            <div className="space-y-0.5">
              <span className="text-sm text-red-400 font-medium">Failed</span>
              {error && (
                <p className="text-xs text-red-400/70 break-all">{error.message}</p>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
