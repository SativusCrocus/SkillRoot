/* ═══════════════════════════════════════════════════════════════
   SkillRoot — Next.js 14 Configuration
   Static export for Fleek / IPFS / Vercel deployment.
   Three.js / R3F transpilation for ESM compatibility.
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

  /* ── Three.js ESM Transpilation ────────────────────────────── */
  transpilePackages: ['three'],

  /* ── Webpack ───────────────────────────────────────────────── */
  webpack: (config) => {
    // RainbowKit + wagmi peer deps excluded from server bundling
    config.externals.push('pino-pretty', 'lokijs', 'encoding');
    return config;
  },
};

module.exports = nextConfig;
