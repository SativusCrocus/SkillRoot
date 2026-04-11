import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/bin.ts'],
  format: ['esm'],
  target: 'node20',
  clean: true,
  sourcemap: true,
  splitting: false,
  bundle: true,
  shims: true,
  // Keep everything external: much smaller binary and no CJS/ESM interop bugs
  external: ['commander', 'kleur', 'ora', 'snarkjs', 'viem'],
});
