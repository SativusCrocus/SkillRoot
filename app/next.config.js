/* ═══════════════════════════════════════════════════════════════
   SkillRoot — Next.js 14 Configuration
   Static export for Fleek / IPFS / Vercel deployment.
   ═══════════════════════════════════════════════════════════════ */

/** @type {import('next').NextConfig} */
const nextConfig = {
  /* ── Static Export ─────────────────────────────────────────── */
  output: 'export',
  trailingSlash: true,
  images: {
    unoptimized: true,
  },

  /* ── React Strict Mode ─────────────────────────────────────── */
  reactStrictMode: true,

  /* ── Webpack ───────────────────────────────────────────────── */
  webpack: (config) => {
    // RainbowKit + wagmi peer deps excluded from server bundling
    config.externals.push('pino-pretty', 'lokijs', 'encoding');
    return config;
  },
};

module.exports = nextConfig;
