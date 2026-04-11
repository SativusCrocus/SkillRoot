/* ═══════════════════════════════════════════════════════════════
   AttestationCard — Glass Attestation Display with Decay
   ═══════════════════════════════════════════════════════════════
   Displays a single attestation record with domain-colored
   accents, animated score bar, signal-strength decay indicator,
   and staggered entrance animation. Used on the /me page to
   show individual attestation records.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import { motion } from 'framer-motion';

export interface AttestationData {
  domain: string;
  domainLabel: string;
  score: string;
  timestamp: number;
  challengeId: number;
  color: string;
  icon: string;
  decayPct: number;
}

interface Props {
  attestation: AttestationData;
  index?: number;
}

export function AttestationCard({ attestation, index = 0 }: Props) {
  const {
    domain,
    domainLabel,
    score,
    challengeId,
    color,
    icon,
    decayPct,
    timestamp,
  } = attestation;

  const date = new Date(timestamp * 1000);
  const timeAgo = getTimeAgo(date);

  return (
    <motion.div
      initial={{ opacity: 0, y: 16, scale: 0.97 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{
        delay: index * 0.08,
        duration: 0.5,
        ease: [0.25, 0.46, 0.45, 0.94],
      }}
      className="glass-card p-5 space-y-4 group hover:border-white/[0.12] transition-all duration-300"
    >
      {/* Header row */}
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-3">
          {/* Domain icon with glow */}
          <div
            className="w-10 h-10 rounded-xl flex items-center justify-center transition-shadow duration-300 group-hover:shadow-glow-xs"
            style={{
              background: `${color}10`,
              border: `1px solid ${color}25`,
            }}
          >
            <span className="text-lg font-mono" style={{ color }}>
              {icon}
            </span>
          </div>
          <div>
            <div className="text-sm font-medium text-silk">{domainLabel}</div>
            <div className="text-2xs text-silk-faint font-mono uppercase tracking-wider">
              {domain}
            </div>
          </div>
        </div>

        {/* Score display */}
        <div className="text-right">
          <div className="text-lg font-mono font-bold" style={{ color }}>
            {score}
          </div>
          <div className="text-2xs text-silk-faint">score</div>
        </div>
      </div>

      {/* Decay progress bar */}
      <div className="space-y-1.5">
        <div className="flex items-center justify-between text-2xs">
          <span className="text-silk-faint">Signal strength</span>
          <span className="text-silk-muted font-mono">{100 - decayPct}%</span>
        </div>
        <div className="relative h-1.5 rounded-full bg-white/[0.04] overflow-hidden">
          <motion.div
            className="absolute inset-y-0 left-0 rounded-full"
            style={{
              background: `linear-gradient(90deg, ${color}66, ${color})`,
              boxShadow: `0 0 8px ${color}30`,
            }}
            initial={{ width: 0 }}
            animate={{ width: `${Math.max(100 - decayPct, 2)}%` }}
            transition={{ delay: 0.3 + index * 0.08, duration: 0.8, ease: 'easeOut' }}
          />
        </div>
      </div>

      {/* Footer metadata */}
      <div className="flex items-center justify-between pt-1 border-t border-white/[0.04]">
        <span className="text-2xs text-silk-faint font-mono">
          Challenge #{challengeId}
        </span>
        <span className="text-2xs text-silk-faint">
          {timeAgo}
        </span>
      </div>
    </motion.div>
  );
}

function getTimeAgo(date: Date): string {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  return date.toLocaleDateString();
}
