/* ═══════════════════════════════════════════════════════════════
   ProofUpload — Silk Drag-Drop Proof Uploader
   ═══════════════════════════════════════════════════════════════
   Drop zone with gradient dashed border, animated drag-over glow,
   file validation with calldata.json schema check, and animated
   state transitions between empty → loaded → error states.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import { useState, useCallback, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

export interface ParsedProof {
  a: readonly [string, string];
  b: readonly [readonly [string, string], readonly [string, string]];
  c: readonly [string, string];
  circuitSignals: readonly string[];
}

interface Props {
  onParsed: (p: ParsedProof) => void;
}

export function ProofUpload({ onParsed }: Props) {
  const [err, setErr] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [signalCount, setSignalCount] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const processFile = useCallback(async (file: File) => {
    setErr(null);
    setFileName(null);
    try {
      const text = await file.text();
      const parsed = JSON.parse(text);
      if (!parsed.a || !parsed.b || !parsed.c || !parsed.circuitSignals) {
        throw new Error('Missing a/b/c/circuitSignals — was this emitted by skr solve?');
      }
      onParsed(parsed as ParsedProof);
      setFileName(file.name);
      setSignalCount(parsed.circuitSignals.length);
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : String(e));
    }
  }, [onParsed]);

  const handleFile = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) processFile(file);
  }, [processFile]);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    const file = e.dataTransfer.files[0];
    if (file) processFile(file);
  }, [processFile]);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
  }, []);

  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-silk-muted uppercase tracking-wider">
        Proof File
      </label>

      {/* Drop zone */}
      <div
        onClick={() => inputRef.current?.click()}
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        className={`
          relative cursor-pointer rounded-xl border-2 border-dashed p-8
          transition-all duration-300 ease-out text-center
          ${isDragging
            ? 'border-neon-cyan/50 bg-neon-cyan/[0.04] shadow-[0_0_30px_-8px_rgba(34,211,238,0.2)]'
            : fileName
              ? 'border-emerald-500/30 bg-emerald-500/[0.03]'
              : 'border-white/[0.08] bg-white/[0.02] hover:border-white/[0.15] hover:bg-white/[0.03]'
          }
        `}
      >
        <input
          ref={inputRef}
          type="file"
          accept="application/json"
          onChange={handleFile}
          className="hidden"
        />

        <AnimatePresence mode="wait">
          {fileName ? (
            <motion.div
              key="loaded"
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="space-y-2"
            >
              {/* Success check */}
              <div className="w-10 h-10 mx-auto rounded-full bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center">
                <svg className="w-5 h-5 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <div className="text-sm text-silk font-medium">{fileName}</div>
              <div className="text-xs text-silk-dim font-mono">
                {signalCount} signal{signalCount !== 1 ? 's' : ''} loaded
              </div>
            </motion.div>
          ) : (
            <motion.div
              key="empty"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="space-y-3"
            >
              {/* Upload icon */}
              <div className={`
                w-12 h-12 mx-auto rounded-xl border flex items-center justify-center
                transition-colors duration-300
                ${isDragging
                  ? 'border-neon-cyan/30 text-neon-cyan'
                  : 'border-white/[0.08] text-silk-muted'
                }
              `}>
                <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5m-13.5-9L12 3m0 0l4.5 4.5M12 3v13.5" />
                </svg>
              </div>
              <div>
                <p className="text-sm text-silk-dim">
                  {isDragging ? 'Drop to upload' : 'Drop calldata.json or click to browse'}
                </p>
                <p className="text-2xs text-silk-faint mt-1">
                  Generated by <code className="font-mono text-neon-cyan/60">skr solve</code>
                </p>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Error display */}
      <AnimatePresence>
        {err && (
          <motion.div
            initial={{ opacity: 0, y: -4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            className="flex items-start gap-2 p-3 rounded-lg bg-red-500/[0.06] border border-red-500/20"
          >
            <span className="status-dot-error mt-0.5 shrink-0" />
            <p className="text-xs text-red-400">{err}</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
