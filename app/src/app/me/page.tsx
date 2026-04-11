/* ═══════════════════════════════════════════════════════════════
   File: src/app/me/page.tsx
   SkillRoot — My Identity / Profile Page
   ═══════════════════════════════════════════════════════════════
   Silk skill-graph visualization showing the user's on-chain
   identity. Glass panels for wallet info, animated neon-gradient
   score bars for each skill domain, staking status, and a
   visual skill-domain radar-style display.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { useAccount, useReadContract } from 'wagmi';
import { ConnectButton } from '@/components/ConnectButton';
import { contracts } from '@/lib/contracts';
import { queryGatewayAbi, stakingVaultAbi, skrTokenAbi } from '@/lib/abis';
import { formatEther } from 'viem';

/* ── Domain Configuration ────────────────────────────────────── */
const DOMAINS = [
  { label: 'ALGO',         fullName: 'Algorithm Design',        color: '#22d3ee', icon: '{}' },
  { label: 'FORMAL_VER',   fullName: 'Formal Verification',     color: '#8b5cf6', icon: '\u2234' },
  { label: 'APPLIED_MATH', fullName: 'Applied Mathematics',     color: '#6366f1', icon: '\u03A3' },
  { label: 'SEC_CODE',     fullName: 'Security & Code Analysis', color: '#a78bfa', icon: '\u26A0' },
] as const;

/* ── Framer Motion Variants ──────────────────────────────────── */
const containerVariants = {
  hidden: {},
  visible: {
    transition: { staggerChildren: 0.12, delayChildren: 0.1 },
  },
};

const fadeUp = {
  hidden: { opacity: 0, y: 24 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.25, 0.46, 0.45, 0.94] },
  },
};

/* ═══════════════════════════════════════════════════════════════ */
export default function MePage() {
  const { address, isConnected } = useAccount();

  /* ── On-Chain Reads ──────────────────────────────────────── */
  const { data: scores } = useReadContract({
    address: contracts.gateway,
    abi: queryGatewayAbi,
    functionName: 'verify',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  const { data: stake } = useReadContract({
    address: contracts.vault,
    abi: stakingVaultAbi,
    functionName: 'stakeOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  const { data: balance } = useReadContract({
    address: contracts.token,
    abi: skrTokenAbi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  /* Helper: format a bigint score to a human-readable number */
  const formatScore = (s: bigint) => {
    if (s === 0n) return '0';
    const raw = formatEther(s);
    const num = parseFloat(raw);
    if (num < 0.01) return '<0.01';
    return num.toFixed(2);
  };

  /* Calculate total score for the progress bar max reference */
  const scoresArray = scores as readonly bigint[] | undefined;
  const maxScore = scoresArray
    ? scoresArray.reduce((max, s) => (s > max ? s : max), 0n)
    : 0n;

  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className="space-y-8"
    >
      {/* ── Navigation ───────────────────────────────────────── */}
      <motion.header
        variants={fadeUp}
        className="flex items-center justify-between"
      >
        <Link
          href="/"
          className="flex items-center gap-2 text-sm text-silk-dim hover:text-neon-cyan transition-colors group"
        >
          <span className="inline-block transition-transform group-hover:-translate-x-1">&larr;</span>
          <span>Home</span>
        </Link>
        <ConnectButton />
      </motion.header>

      {/* ── Page Title ───────────────────────────────────────── */}
      <motion.div variants={fadeUp} className="space-y-2">
        <h1 className="text-display-sm text-gradient">My Identity</h1>
        <p className="text-sm text-silk-dim">
          Your on-chain skill profile, stake position, and decayed attestation scores.
        </p>
      </motion.div>

      {/* ── Not Connected State ──────────────────────────────── */}
      {!isConnected ? (
        <motion.div variants={fadeUp}>
          <div className="glass-card-strong p-10 sm:p-16 text-center space-y-6 gradient-border">
            {/* Placeholder orb */}
            <div className="relative mx-auto w-20 h-20">
              <div className="absolute inset-0 rounded-full bg-gradient-to-br from-neon-cyan/10 to-neon-violet/10 blur-xl animate-pulse-glow" />
              <div className="relative w-20 h-20 rounded-full border border-white/[0.08] flex items-center justify-center">
                <span className="text-2xl text-silk-faint">?</span>
              </div>
            </div>
            <div className="space-y-2">
              <p className="text-silk-dim text-sm">Connect a wallet to view your attestations.</p>
              <p className="text-silk-faint text-xs">Your skill graph is read directly from on-chain state.</p>
            </div>
          </div>
        </motion.div>
      ) : (
        <>
          {/* ── Wallet Overview Card ─────────────────────────── */}
          <motion.div variants={fadeUp}>
            <div className="glass-card p-6 sm:p-8 space-y-4">
              <div className="flex items-center gap-3 mb-1">
                <h2 className="text-sm font-semibold text-silk uppercase tracking-wider">Wallet</h2>
                <span className="status-dot" />
              </div>

              {/* Address */}
              <div className="glass-subtle p-3 space-y-1">
                <div className="text-xs text-silk-muted">Address</div>
                <code className="text-xs sm:text-sm text-neon-cyan font-mono break-all">
                  {address}
                </code>
              </div>

              {/* Balance + Stake row */}
              <div className="grid grid-cols-2 gap-4">
                <div className="glass-subtle p-4 space-y-1">
                  <div className="text-xs text-silk-muted">SKR Balance</div>
                  <div className="text-lg font-semibold text-silk font-mono">
                    {balance ? formatEther(balance as bigint) : '0'}
                  </div>
                </div>
                <div className="glass-subtle p-4 space-y-1">
                  <div className="text-xs text-silk-muted">Staked</div>
                  <div className="text-lg font-semibold text-silk font-mono">
                    {stake ? formatEther(stake as bigint) : '0'}
                  </div>
                </div>
              </div>
            </div>
          </motion.div>

          {/* ── Skill Scores — Visual Bars ────────────────────── */}
          <motion.div variants={fadeUp}>
            <div className="glass-card-strong p-6 sm:p-8 space-y-6 gradient-border">
              <div className="flex items-center gap-3">
                <h2 className="text-sm font-semibold text-silk uppercase tracking-wider">
                  Decayed Skill Scores
                </h2>
                <hr className="neon-divider flex-1" />
              </div>

              {scoresArray ? (
                <div className="space-y-5">
                  {DOMAINS.map((domain, i) => {
                    const score = scoresArray[i] ?? 0n;
                    const hasScore = score > 0n;
                    /*
                      Progress bar width — relative to the max score
                      across all domains. If all are 0, show empty bars.
                    */
                    const pct = maxScore > 0n
                      ? Number((score * 100n) / maxScore)
                      : 0;

                    return (
                      <motion.div
                        key={domain.label}
                        initial={{ opacity: 0, x: -16 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ delay: 0.3 + i * 0.1, duration: 0.5 }}
                        className="space-y-2"
                      >
                        {/* Domain header row */}
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2.5">
                            <span
                              className="text-base font-mono"
                              style={{ color: domain.color }}
                            >
                              {domain.icon}
                            </span>
                            <div>
                              <div className="text-sm font-medium text-silk">
                                {domain.fullName}
                              </div>
                              <div className="text-2xs text-silk-faint font-mono uppercase tracking-wider">
                                {domain.label}
                              </div>
                            </div>
                          </div>
                          <div className="text-right">
                            <span
                              className="text-sm font-mono font-semibold"
                              style={{ color: hasScore ? domain.color : 'var(--silk-faint)' }}
                            >
                              {hasScore ? formatScore(score) : '\u2014'}
                            </span>
                          </div>
                        </div>

                        {/* Score bar */}
                        <div className="relative h-2 rounded-full bg-white/[0.04] overflow-hidden">
                          <motion.div
                            className="absolute inset-y-0 left-0 rounded-full"
                            style={{
                              background: `linear-gradient(90deg, ${domain.color}88, ${domain.color})`,
                              boxShadow: hasScore ? `0 0 12px ${domain.color}40` : 'none',
                            }}
                            initial={{ width: 0 }}
                            animate={{ width: hasScore ? `${Math.max(pct, 4)}%` : '0%' }}
                            transition={{ delay: 0.5 + i * 0.12, duration: 0.8, ease: 'easeOut' }}
                          />
                        </div>
                      </motion.div>
                    );
                  })}
                </div>
              ) : (
                /* Loading / no data state */
                <div className="text-center py-6 space-y-2">
                  <p className="text-sm text-silk-muted">No attestation data found.</p>
                  <p className="text-xs text-silk-faint">
                    Complete a challenge to build your skill graph.
                  </p>
                </div>
              )}
            </div>
          </motion.div>

          {/* ── Skill Graph Visual — Domain Nodes ────────────── */}
          <motion.div variants={fadeUp}>
            <div className="glass-card p-6 sm:p-8 space-y-4">
              <h2 className="text-sm font-semibold text-silk uppercase tracking-wider">
                Skill Graph
              </h2>

              {/* Mini node visualization — shows domain connectivity */}
              <div className="relative mx-auto w-full max-w-sm aspect-square perspective-container">
                {/* Center identity node */}
                <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-10">
                  <div className="relative">
                    <div className="absolute -inset-4 rounded-full bg-gradient-to-br from-neon-cyan/15 to-neon-violet/15 blur-lg animate-pulse-glow" />
                    <div className="relative w-12 h-12 rounded-full bg-gradient-to-br from-neon-cyan to-neon-violet shadow-glow flex items-center justify-center">
                      <span className="text-void font-bold text-xs">YOU</span>
                    </div>
                  </div>
                </div>

                {/* Domain nodes positioned around the center */}
                {DOMAINS.map((domain, i) => {
                  const score = scoresArray?.[i] ?? 0n;
                  const hasScore = score > 0n;
                  const angleRad = ((i * 90 - 90) * Math.PI) / 180;
                  const radius = 100;
                  const x = Math.cos(angleRad) * radius;
                  const y = Math.sin(angleRad) * radius;

                  return (
                    <motion.div
                      key={domain.label}
                      className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2"
                      style={{ x, y }}
                      animate={{
                        y: [y, y - 6, y + 3, y],
                      }}
                      transition={{
                        duration: 4 + i * 0.5,
                        repeat: Infinity,
                        ease: 'easeInOut',
                        delay: i * 0.3,
                      }}
                    >
                      {/* Connection line to center */}
                      <svg
                        className="absolute top-1/2 left-1/2 -z-10 pointer-events-none overflow-visible"
                        width="1"
                        height="1"
                        aria-hidden="true"
                      >
                        <line
                          x1="0"
                          y1="0"
                          x2={-x}
                          y2={-y}
                          stroke={domain.color}
                          strokeOpacity={hasScore ? 0.25 : 0.06}
                          strokeWidth={hasScore ? 1.5 : 1}
                          strokeDasharray={hasScore ? 'none' : '4 4'}
                        />
                      </svg>

                      {/* Node */}
                      <div
                        className={`glass-card px-3 py-2 flex flex-col items-center gap-1 min-w-[56px] transition-all duration-500 ${
                          hasScore
                            ? 'border-white/[0.12] shadow-glow-xs'
                            : 'opacity-50'
                        }`}
                      >
                        <span
                          className="text-lg font-mono"
                          style={{ color: domain.color }}
                        >
                          {domain.icon}
                        </span>
                        <span className="text-2xs text-silk-dim font-medium tracking-wider uppercase whitespace-nowrap">
                          {domain.label.replace('_', ' ')}
                        </span>
                        {hasScore && (
                          <span
                            className="text-2xs font-mono font-semibold"
                            style={{ color: domain.color }}
                          >
                            {formatScore(score)}
                          </span>
                        )}
                      </div>
                    </motion.div>
                  );
                })}
              </div>
            </div>
          </motion.div>

          {/* ── Quick Actions ─────────────────────────────────── */}
          <motion.div variants={fadeUp} className="flex flex-col sm:flex-row gap-3">
            <Link href="/submit" className="btn-primary flex-1 text-center">
              Submit New Proof
            </Link>
            <Link href="/" className="btn-silk flex-1 text-center">
              Back to Dashboard
            </Link>
          </motion.div>
        </>
      )}
    </motion.div>
  );
}
