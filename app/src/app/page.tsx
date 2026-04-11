/* ═══════════════════════════════════════════════════════════════
   File: src/app/page.tsx
   SkillRoot — Landing Page
   ═══════════════════════════════════════════════════════════════
   3D hero section with floating capability nodes orbiting a
   central protocol identity. Ambient particle field provides
   depth. Glass challenge card shows on-chain state. Full
   Framer Motion staggered entrance animations throughout.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { motion } from 'framer-motion';
import { ConnectButton } from '@/components/ConnectButton';
import { useReadContract } from 'wagmi';
import { contracts } from '@/lib/contracts';
import { challengeRegistryAbi } from '@/lib/abis';

/* ── Skill-Domain Node Data ──────────────────────────────────── */
const DOMAINS = [
  { label: 'ALGO',        icon: '{}',  color: '#22d3ee', angle: 0   },
  { label: 'FORMAL_VER',  icon: '\u2234',  color: '#8b5cf6', angle: 90  },
  { label: 'APPLIED_MATH',icon: '\u03A3',  color: '#6366f1', angle: 180 },
  { label: 'SEC_CODE',    icon: '\u26A0',  color: '#a78bfa', angle: 270 },
] as const;

/* ── Floating Particles ──────────────────────────────────────── */
/* Deterministic seeded PRNG to avoid server/client hydration mismatch */
function seededRandom(seed: number) {
  const x = Math.sin(seed * 9301 + 49297) * 49297;
  return x - Math.floor(x);
}

const PARTICLES = Array.from({ length: 20 }, (_, i) => ({
  id: i,
  x: seededRandom(i * 7 + 1) * 100,
  y: seededRandom(i * 7 + 2) * 100,
  size: seededRandom(i * 7 + 3) * 3 + 1,
  duration: seededRandom(i * 7 + 4) * 15 + 15,
  delay: seededRandom(i * 7 + 5) * 8,
  opacity: seededRandom(i * 7 + 6) * 0.4 + 0.1,
  isViolet: seededRandom(i * 7 + 7) > 0.6,
}));

/* ── Protocol Stats (static for v0) ──────────────────────────── */
const STATS = [
  { label: 'Circuit',    value: 'Groth16' },
  { label: 'Domain',     value: 'modexp' },
  { label: 'Network',    value: 'Base Sepolia' },
  { label: 'Supply',     value: '100M SKR' },
];

/* ── Framer Motion Variants ──────────────────────────────────── */
const containerVariants = {
  hidden: {},
  visible: {
    transition: { staggerChildren: 0.15, delayChildren: 0.2 },
  },
};

const fadeUp = {
  hidden: { opacity: 0, y: 32 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.8, ease: [0.25, 0.46, 0.45, 0.94] },
  },
};

const scaleIn = {
  hidden: { opacity: 0, scale: 0.85 },
  visible: {
    opacity: 1,
    scale: 1,
    transition: { duration: 0.6, ease: [0.25, 0.46, 0.45, 0.94] },
  },
};

/* ═══════════════════════════════════════════════════════════════ */
export default function Home() {
  /* ── Client-only flag for hydration-safe particles ────── */
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  /* ── On-Chain Data ───────────────────────────────────────── */
  const { data: nextId } = useReadContract({
    address: contracts.registry,
    abi: challengeRegistryAbi,
    functionName: 'nextChallengeId',
  });

  const { data: challenge } = useReadContract({
    address: contracts.registry,
    abi: challengeRegistryAbi,
    functionName: 'getChallenge',
    args: [BigInt(1)],
  });

  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className="space-y-16 sm:space-y-24"
    >
      {/* ══════════════════════════════════════════════════════
          Navigation Bar
          ══════════════════════════════════════════════════════ */}
      <motion.header
        variants={fadeUp}
        className="flex items-center justify-between"
      >
        {/* Logo mark — SVG logo with protocol name */}
        <Link href="/" className="flex items-center gap-3 group">
          <Image
            src="/logo.svg"
            alt="SkillRoot"
            width={36}
            height={36}
            className="rounded-lg shadow-glow-sm transition-shadow group-hover:shadow-glow"
          />
          <span className="font-semibold text-silk tracking-tight text-lg">
            SkillRoot
          </span>
        </Link>
        <ConnectButton />
      </motion.header>

      {/* ══════════════════════════════════════════════════════
          Hero Section — 3D Floating Skill Graph
          ══════════════════════════════════════════════════════ */}
      <section className="relative">
        {/* ── Ambient Particle Field ──
            Absolute-positioned dots that drift organically,
            creating a star-field depth effect behind the hero. */}
        <div className="absolute inset-0 overflow-hidden pointer-events-none -z-10" aria-hidden="true">
          {mounted && PARTICLES.map((p) => (
            <motion.div
              key={p.id}
              className={`absolute rounded-full ${p.isViolet ? 'bg-neon-violet' : 'bg-neon-cyan'}`}
              style={{
                width: p.size,
                height: p.size,
                left: `${p.x}%`,
                top: `${p.y}%`,
                opacity: p.opacity,
                boxShadow: `0 0 ${p.size * 3}px ${p.isViolet ? 'rgba(139,92,246,0.5)' : 'rgba(34,211,238,0.5)'}`,
              }}
              animate={{
                y: [0, -30, 10, -20, 0],
                x: [0, 15, -10, 5, 0],
                opacity: [p.opacity, p.opacity * 1.8, p.opacity * 0.6, p.opacity * 1.4, p.opacity],
              }}
              transition={{
                duration: p.duration,
                repeat: Infinity,
                delay: p.delay,
                ease: 'easeInOut',
              }}
            />
          ))}
        </div>

        {/* ── Hero Content ── */}
        <div className="relative text-center space-y-8 py-8 sm:py-16">
          {/* Protocol badge */}
          <motion.div variants={fadeUp}>
            <span className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full glass-subtle text-xs font-medium text-silk-dim tracking-wide uppercase">
              <span className="status-dot" />
              Testnet Live
            </span>
          </motion.div>

          {/* Main headline — gradient text with glow */}
          <motion.h1
            variants={fadeUp}
            className="text-display-sm sm:text-display text-gradient-shimmer leading-tight"
          >
            Human Capability
            <br />
            Signaling
          </motion.h1>

          {/* Tagline */}
          <motion.p
            variants={fadeUp}
            className="text-silk-dim text-base sm:text-lg max-w-2xl mx-auto leading-relaxed"
          >
            The Bitcoin-level primitive for skill attestation. Prove knowledge
            with zero-knowledge proofs, verified by stake-weighted committees,
            recorded permanently on-chain.
          </motion.p>

          {/* CTA buttons */}
          <motion.div variants={fadeUp} className="flex items-center justify-center gap-4">
            <Link href="/submit" className="btn-primary">
              Submit Proof
            </Link>
            <Link href="/me" className="btn-silk">
              View Profile
            </Link>
          </motion.div>
        </div>

        {/* ── 3D Skill-Domain Orbit ──
            Four domain nodes orbit a central core using CSS
            transforms. Each node is a glass hexagon with the
            domain icon and a neon glow matching its colour.
            Pure CSS 3D — no WebGL required. */}
        <motion.div
          variants={scaleIn}
          className="relative mx-auto w-[280px] h-[280px] sm:w-[360px] sm:h-[360px] mt-8 perspective-container"
        >
          {/* Central core — pulsing orb */}
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="relative">
              {/* Outer glow ring */}
              <div className="absolute -inset-6 rounded-full bg-gradient-to-br from-neon-cyan/20 to-neon-violet/20 blur-xl animate-pulse-glow" />
              {/* Inner orb — logo mark */}
              <div className="relative w-16 h-16 sm:w-20 sm:h-20 rounded-full overflow-hidden shadow-glow-lg">
                <Image src="/logo.svg" alt="SkillRoot" width={80} height={80} className="w-full h-full" />
              </div>
            </div>
          </div>

          {/* Orbit ring — subtle glass circle */}
          <div className="absolute inset-8 sm:inset-10 rounded-full border border-white/[0.04]" />

          {/* Domain nodes — positioned at cardinal points and orbiting */}
          {DOMAINS.map((domain, i) => {
            /* Calculate position on the orbit circle */
            const radius = 120; /* px from center */
            const angleRad = ((domain.angle - 90) * Math.PI) / 180;
            const x = Math.cos(angleRad) * radius;
            const y = Math.sin(angleRad) * radius;

            return (
              <motion.div
                key={domain.label}
                className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2"
                style={{ x, y }}
                animate={{
                  y: [y, y - 8, y + 4, y],
                  scale: [1, 1.05, 0.98, 1],
                }}
                transition={{
                  duration: 5 + i * 0.7,
                  repeat: Infinity,
                  ease: 'easeInOut',
                  delay: i * 0.4,
                }}
              >
                {/* Node glow backdrop */}
                <div
                  className="absolute -inset-3 rounded-xl blur-lg opacity-30"
                  style={{ background: domain.color }}
                />
                {/* Glass node surface */}
                <div className="relative glass-card px-3 py-2 sm:px-4 sm:py-3 flex flex-col items-center gap-1 min-w-[60px] sm:min-w-[72px] cursor-default group">
                  {/* Domain icon */}
                  <span
                    className="text-lg sm:text-xl font-mono transition-transform duration-300 group-hover:scale-110"
                    style={{ color: domain.color }}
                  >
                    {domain.icon}
                  </span>
                  {/* Domain label */}
                  <span className="text-2xs font-medium text-silk-dim tracking-wider uppercase whitespace-nowrap">
                    {domain.label.replace('_', ' ')}
                  </span>
                  {/* Connection line to center (SVG) */}
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
                      strokeOpacity="0.12"
                      strokeWidth="1"
                      strokeDasharray="4 4"
                    />
                  </svg>
                </div>
              </motion.div>
            );
          })}
        </motion.div>
      </section>

      {/* ══════════════════════════════════════════════════════
          Protocol Stats Bar
          ══════════════════════════════════════════════════════ */}
      <motion.section variants={fadeUp}>
        <div className="glass-card p-6 sm:p-8">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-6 sm:gap-8">
            {STATS.map((stat, i) => (
              <motion.div
                key={stat.label}
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.8 + i * 0.1, duration: 0.5 }}
                className="text-center space-y-1"
              >
                <div className="text-xs font-medium text-silk-muted uppercase tracking-widest">
                  {stat.label}
                </div>
                <div className="text-sm sm:text-base font-semibold text-silk font-mono">
                  {stat.value}
                </div>
              </motion.div>
            ))}
          </div>
        </div>
      </motion.section>

      {/* ══════════════════════════════════════════════════════
          Active Challenge Card
          ══════════════════════════════════════════════════════ */}
      <motion.section variants={fadeUp} className="space-y-4">
        <div className="flex items-center gap-3 mb-2">
          <h2 className="text-lg font-semibold text-silk">Active Challenge</h2>
          <hr className="neon-divider flex-1" />
        </div>

        <div className="glass-card-strong p-6 sm:p-8 gradient-border">
          {challenge && challenge.status === 1 ? (
            <div className="space-y-5">
              {/* Challenge header */}
              <div className="flex items-start justify-between gap-4">
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="status-dot" />
                    <span className="text-sm font-medium text-silk">
                      Challenge #{String(challenge.id)}
                    </span>
                  </div>
                  <div className="text-xs text-silk-muted font-mono uppercase tracking-wider">
                    APPLIED_MATH &mdash; Modular Exponentiation
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-xs text-silk-muted">Signal Weight</div>
                  <div className="text-sm font-mono text-neon-cyan font-semibold">
                    {String(challenge.signalWeight)}
                  </div>
                </div>
              </div>

              {/* Verifier address */}
              <div className="glass-subtle p-3 space-y-1">
                <div className="text-xs text-silk-muted">Verifier Contract</div>
                <code className="text-xs sm:text-sm text-neon-cyan font-mono break-all">
                  {challenge.verifier}
                </code>
              </div>

              {/* Actions */}
              <div className="flex flex-col sm:flex-row gap-3 pt-2">
                <Link href="/submit" className="btn-primary flex-1 text-center">
                  Submit Proof
                </Link>
                <Link href="/me" className="btn-silk flex-1 text-center">
                  View Attestations
                </Link>
              </div>
            </div>
          ) : (
            /* No active challenge state */
            <div className="text-center py-8 space-y-3">
              <div className="w-12 h-12 mx-auto rounded-full border border-white/[0.06] flex items-center justify-center">
                <span className="text-silk-muted text-xl">&mdash;</span>
              </div>
              <div className="text-sm text-silk-muted">
                No active challenge.
                {nextId !== undefined && (
                  <span className="font-mono text-silk-faint ml-2">
                    nextId={String(nextId)}
                  </span>
                )}
              </div>
            </div>
          )}
        </div>
      </motion.section>

      {/* ══════════════════════════════════════════════════════
          How It Works — Three-step flow
          ══════════════════════════════════════════════════════ */}
      <motion.section variants={fadeUp} className="space-y-6">
        <div className="flex items-center gap-3 mb-2">
          <h2 className="text-lg font-semibold text-silk">How It Works</h2>
          <hr className="neon-divider flex-1" />
        </div>

        <div className="grid sm:grid-cols-3 gap-4 sm:gap-6">
          {[
            {
              step: '01',
              title: 'Prove',
              desc: 'Solve a challenge off-chain and generate a Groth16 zero-knowledge proof with the CLI.',
              accent: '#22d3ee',
            },
            {
              step: '02',
              title: 'Attest',
              desc: 'Submit your proof on-chain. A stake-weighted validator committee reviews and votes.',
              accent: '#8b5cf6',
            },
            {
              step: '03',
              title: 'Signal',
              desc: 'Accepted attestations become permanent, decayed skill scores readable by any dApp.',
              accent: '#6366f1',
            },
          ].map((item, i) => (
            <motion.div
              key={item.step}
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 1.0 + i * 0.15, duration: 0.6 }}
              className="glass-card p-5 sm:p-6 space-y-3 group hover:border-white/[0.12] transition-colors"
            >
              {/* Step number with accent glow */}
              <div className="flex items-center gap-3">
                <span
                  className="text-xs font-mono font-bold tracking-widest"
                  style={{ color: item.accent }}
                >
                  {item.step}
                </span>
                <hr className="glass-divider flex-1" />
              </div>
              <h3 className="text-base font-semibold text-silk">{item.title}</h3>
              <p className="text-sm text-silk-dim leading-relaxed">{item.desc}</p>
            </motion.div>
          ))}
        </div>
      </motion.section>

      {/* ══════════════════════════════════════════════════════
          Footer
          ══════════════════════════════════════════════════════ */}
      <motion.footer variants={fadeUp} className="pt-4 pb-2">
        <hr className="glass-divider mb-6" />
        <div className="flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-silk-faint">
          <span>SkillRoot v0 &mdash; Testnet Only &mdash; Unaudited</span>
          <div className="flex items-center gap-4">
            <Link href="/submit" className="hover:text-silk-dim transition-colors">
              Submit
            </Link>
            <Link href="/me" className="hover:text-silk-dim transition-colors">
              Profile
            </Link>
          </div>
        </div>
      </motion.footer>
    </motion.div>
  );
}
