import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { base, baseSepolia } from 'wagmi/chains';

// Fleek-hosted static export needs all public env vars at build time.
const projectId = process.env.NEXT_PUBLIC_WC_PROJECT_ID || 'skillroot-dev';

export const wagmiConfig = getDefaultConfig({
  appName: 'SkillRoot',
  projectId,
  chains: [baseSepolia, base],
  ssr: false,
});

export const supportedChainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID || 84532);
