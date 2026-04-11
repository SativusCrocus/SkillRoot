/* ═══════════════════════════════════════════════════════════════
   SkillGraphScene — 3D Identity Skill Graph
   ═══════════════════════════════════════════════════════════════
   Interactive skill-graph for the /me page. Central identity
   node surrounded by four domain spheres sized by decayed
   on-chain score. Connection beams brighten for active domains.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import { useRef, Suspense } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { Float, Stars, Line } from '@react-three/drei';
import * as THREE from 'three';

/* ── Public type used by me/page.tsx ──────────────────────────── */
export interface DomainScore {
  label: string;
  color: string;
  /** 0–1 normalised score (relative to max domain) */
  score: number;
  hasScore: boolean;
}

const GRAPH_RADIUS = 2;

/* ── Central Identity Node ────────────────────────────────────── */
function IdentityNode() {
  const ref = useRef<THREE.Mesh>(null!);

  useFrame(({ clock }) => {
    ref.current.rotation.y = clock.elapsedTime * 0.2;
    ref.current.rotation.x = Math.sin(clock.elapsedTime * 0.15) * 0.06;
  });

  return (
    <Float speed={1.2} rotationIntensity={0.12} floatIntensity={0.25}>
      <mesh ref={ref}>
        <dodecahedronGeometry args={[0.45, 1]} />
        <meshStandardMaterial
          color="#0e1230"
          emissive="#22d3ee"
          emissiveIntensity={0.35}
          roughness={0.15}
          metalness={0.88}
        />
      </mesh>
      {/* Outer glow halo */}
      <mesh scale={1.45}>
        <sphereGeometry args={[0.45, 16, 16]} />
        <meshBasicMaterial
          color="#22d3ee"
          transparent
          opacity={0.03}
          side={THREE.BackSide}
        />
      </mesh>
    </Float>
  );
}

/* ── Score Node — size and brightness scale with score ────────── */
function ScoreNode({
  domain,
  index,
}: {
  domain: DomainScore;
  index: number;
}) {
  const ref = useRef<THREE.Group>(null!);
  const angleRad = ((index * 90 - 90) * Math.PI) / 180;
  const x = Math.cos(angleRad) * GRAPH_RADIUS;
  const z = Math.sin(angleRad) * GRAPH_RADIUS;
  const scale = domain.hasScore ? 0.8 + domain.score * 0.8 : 0.6;

  useFrame(({ clock }) => {
    const t = clock.elapsedTime + index * 1.3;
    ref.current.position.y = Math.sin(t * 0.45) * 0.18;
  });

  return (
    <group ref={ref} position={[x, 0, z]}>
      <Float speed={0.9 + index * 0.2} rotationIntensity={0.25} floatIntensity={0.2}>
        <mesh scale={scale}>
          <icosahedronGeometry args={[0.18, 1]} />
          <meshStandardMaterial
            color={domain.color}
            emissive={domain.color}
            emissiveIntensity={domain.hasScore ? 0.55 : 0.12}
            roughness={0.25}
            metalness={0.75}
            transparent
            opacity={domain.hasScore ? 1 : 0.35}
          />
        </mesh>
        {/* Glow halo — only when score > 0 */}
        {domain.hasScore && (
          <mesh scale={scale * 1.8}>
            <sphereGeometry args={[0.18, 12, 12]} />
            <meshBasicMaterial color={domain.color} transparent opacity={0.05} />
          </mesh>
        )}
      </Float>
    </group>
  );
}

/* ── Connection Line — solid for scored, dashed for empty ────── */
function ConnectionLine({
  index,
  color,
  hasScore,
}: {
  index: number;
  color: string;
  hasScore: boolean;
}) {
  const angleRad = ((index * 90 - 90) * Math.PI) / 180;
  return (
    <Line
      points={[
        [0, 0, 0],
        [Math.cos(angleRad) * GRAPH_RADIUS, 0, Math.sin(angleRad) * GRAPH_RADIUS],
      ]}
      color={color}
      transparent
      opacity={hasScore ? 0.18 : 0.04}
      lineWidth={hasScore ? 1.5 : 1}
      dashed={!hasScore}
      dashScale={8}
      dashSize={0.3}
      gapSize={0.3}
    />
  );
}

/* ── Composed Graph Scene ─────────────────────────────────────── */
function GraphScene({ domains }: { domains: DomainScore[] }) {
  const groupRef = useRef<THREE.Group>(null!);

  useFrame(({ clock }) => {
    groupRef.current.rotation.y = clock.elapsedTime * 0.035;
  });

  return (
    <>
      <ambientLight intensity={0.08} />
      <pointLight position={[2, 4, 3]} intensity={0.55} color="#22d3ee" distance={14} />
      <pointLight position={[-3, -1, -4]} intensity={0.28} color="#8b5cf6" distance={14} />

      <Stars radius={14} depth={28} count={350} factor={2} saturation={0} fade speed={0.3} />

      <group ref={groupRef}>
        <IdentityNode />
        {domains.map((d, i) => (
          <ScoreNode key={d.label} domain={d} index={i} />
        ))}
        {domains.map((d, i) => (
          <ConnectionLine key={`l-${d.label}`} index={i} color={d.color} hasScore={d.hasScore} />
        ))}
      </group>
    </>
  );
}

/* ── Exported Canvas ──────────────────────────────────────────── */
export default function SkillGraphScene({ domains }: { domains: DomainScore[] }) {
  return (
    <Canvas
      camera={{ position: [0, 1.6, 4], fov: 40 }}
      gl={{ alpha: true, antialias: true, powerPreference: 'high-performance' }}
      style={{ background: 'transparent' }}
      dpr={[1, 2]}
    >
      <Suspense fallback={null}>
        <GraphScene domains={domains} />
      </Suspense>
    </Canvas>
  );
}
