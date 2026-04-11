/* ═══════════════════════════════════════════════════════════════
   SkillOrbScene — 3D Hero Skill-Domain Orbit
   ═══════════════════════════════════════════════════════════════
   Central distorted orb surrounded by four crystalline domain
   nodes on an orbital ring. Stars background, dual-coloured
   point lights, gentle auto-rotation. Pure Three.js via R3F.
   ═══════════════════════════════════════════════════════════════ */

'use client';

import { useRef, useMemo, Suspense } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { Float, MeshDistortMaterial, Stars, Line } from '@react-three/drei';
import * as THREE from 'three';

/* ── Domain Palette (matches contract-side enum order) ────────── */
const DOMAINS = [
  { color: '#22d3ee', angle: 0 },
  { color: '#8b5cf6', angle: 90 },
  { color: '#6366f1', angle: 180 },
  { color: '#a78bfa', angle: 270 },
] as const;

const ORBIT_RADIUS = 2.6;

/* ── Central Orb ──────────────────────────────────────────────── */
function CentralOrb() {
  const ref = useRef<THREE.Mesh>(null!);

  useFrame(({ clock }) => {
    ref.current.rotation.y = clock.elapsedTime * 0.15;
    ref.current.rotation.x = Math.sin(clock.elapsedTime * 0.25) * 0.08;
  });

  return (
    <Float speed={1.4} rotationIntensity={0.15} floatIntensity={0.4}>
      {/* Primary distorted sphere — dark base, cyan emissive glow */}
      <mesh ref={ref}>
        <icosahedronGeometry args={[0.75, 12]} />
        <MeshDistortMaterial
          color="#0e1230"
          emissive="#22d3ee"
          emissiveIntensity={0.4}
          roughness={0.12}
          metalness={0.92}
          distort={0.22}
          speed={1.8}
        />
      </mesh>
      {/* Outer glow shell — violet tint, backside only */}
      <mesh scale={1.35}>
        <icosahedronGeometry args={[0.75, 6]} />
        <meshBasicMaterial
          color="#8b5cf6"
          transparent
          opacity={0.025}
          side={THREE.BackSide}
        />
      </mesh>
    </Float>
  );
}

/* ── Domain Node — crystalline octahedron with glow halo ──────── */
function DomainNode({
  angle,
  color,
  index,
}: {
  angle: number;
  color: string;
  index: number;
}) {
  const ref = useRef<THREE.Group>(null!);
  const rad = ((angle - 90) * Math.PI) / 180;
  const x = Math.cos(rad) * ORBIT_RADIUS;
  const z = Math.sin(rad) * ORBIT_RADIUS;

  useFrame(({ clock }) => {
    const t = clock.elapsedTime + index * 1.6;
    ref.current.position.y = Math.sin(t * 0.55) * 0.22;
  });

  return (
    <group ref={ref} position={[x, 0, z]}>
      <Float
        speed={1.1 + index * 0.25}
        rotationIntensity={0.35}
        floatIntensity={0.25}
      >
        <mesh>
          <octahedronGeometry args={[0.2, 0]} />
          <meshStandardMaterial
            color={color}
            emissive={color}
            emissiveIntensity={0.55}
            roughness={0.18}
            metalness={0.82}
          />
        </mesh>
        <mesh scale={2.2}>
          <sphereGeometry args={[0.2, 16, 16]} />
          <meshBasicMaterial color={color} transparent opacity={0.05} />
        </mesh>
      </Float>
    </group>
  );
}

/* ── Orbit Ring — thin circular line ──────────────────────────── */
function OrbitRing() {
  const points = useMemo(() => {
    const pts: [number, number, number][] = [];
    for (let i = 0; i <= 128; i++) {
      const a = (i / 128) * Math.PI * 2;
      pts.push([Math.cos(a) * ORBIT_RADIUS, 0, Math.sin(a) * ORBIT_RADIUS]);
    }
    return pts;
  }, []);

  return <Line points={points} color="#ffffff" transparent opacity={0.04} lineWidth={1} />;
}

/* ── Connection Beam — dashed line from center to node ────────── */
function ConnectionBeam({ angle, color }: { angle: number; color: string }) {
  const rad = ((angle - 90) * Math.PI) / 180;
  return (
    <Line
      points={[
        [0, 0, 0],
        [Math.cos(rad) * ORBIT_RADIUS, 0, Math.sin(rad) * ORBIT_RADIUS],
      ]}
      color={color}
      transparent
      opacity={0.07}
      lineWidth={1}
      dashed
      dashScale={8}
      dashSize={0.4}
      gapSize={0.4}
    />
  );
}

/* ── Composed Scene ───────────────────────────────────────────── */
function Scene() {
  const groupRef = useRef<THREE.Group>(null!);

  useFrame(({ clock }) => {
    groupRef.current.rotation.y = clock.elapsedTime * 0.04;
  });

  return (
    <>
      <ambientLight intensity={0.1} />
      <pointLight position={[3, 5, 4]} intensity={0.7} color="#22d3ee" distance={20} />
      <pointLight position={[-4, -2, -5]} intensity={0.35} color="#8b5cf6" distance={20} />

      <Stars radius={18} depth={40} count={700} factor={2.5} saturation={0} fade speed={0.4} />

      <group ref={groupRef}>
        <CentralOrb />
        <OrbitRing />
        {DOMAINS.map((d, i) => (
          <DomainNode key={i} angle={d.angle} color={d.color} index={i} />
        ))}
        {DOMAINS.map((d, i) => (
          <ConnectionBeam key={`b${i}`} angle={d.angle} color={d.color} />
        ))}
      </group>
    </>
  );
}

/* ── Exported Canvas ──────────────────────────────────────────── */
export default function SkillOrbScene() {
  return (
    <Canvas
      camera={{ position: [0, 2, 5.5], fov: 42 }}
      gl={{ alpha: true, antialias: true, powerPreference: 'high-performance' }}
      style={{ background: 'transparent' }}
      dpr={[1, 2]}
    >
      <Suspense fallback={null}>
        <Scene />
      </Suspense>
    </Canvas>
  );
}
