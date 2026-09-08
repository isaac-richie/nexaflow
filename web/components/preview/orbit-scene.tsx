"use client";

import { Suspense, useEffect, useMemo, useRef } from "react";
import { Canvas, useFrame, useLoader, useThree } from "@react-three/fiber";
import { ACESFilmicToneMapping, ExtrudeGeometry, FileLoader, Group, MathUtils, PMREMGenerator } from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { SVGLoader } from "three/examples/jsm/loaders/SVGLoader.js";
import { HERO_FRAME_INTERVAL_MS } from "@/lib/preview/animation-policy";

function StudioLight() {
  const { gl, scene } = useThree();
  useEffect(() => {
    const generator = new PMREMGenerator(gl);
    const room = new RoomEnvironment();
    const target = generator.fromScene(room, 0.04);
    const previous = scene.environment;
    scene.environment = target.texture;
    room.dispose(); generator.dispose();
    return () => { scene.environment = previous; target.dispose(); };
  }, [gl, scene]);
  return <><ambientLight intensity={0.6}/><directionalLight position={[3, 4, 5]} intensity={3} color="#ffe6b7"/><directionalLight position={[-4, 0, 2]} intensity={1.5} color="#f2f4ff"/></>;
}

function FrameDriver({ running }: { running: boolean }) {
  const advance = useThree(state => state.advance);
  const elapsed = useRef(0);
  useEffect(() => {
    let handle = 0;
    let last = performance.now();
    // R3F's manual clock takes seconds. Preserve time through pause/resume.
    advance(elapsed.current);
    function tick(now: number) {
      const delta = now - last;
      if (delta >= HERO_FRAME_INTERVAL_MS) {
        elapsed.current += Math.min(delta / 1000, 0.1);
        last = now - (delta % HERO_FRAME_INTERVAL_MS);
        advance(elapsed.current);
      }
      handle = requestAnimationFrame(tick);
    }
    if (running) handle = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(handle);
  }, [advance, running]);
  return null;
}

function Sculpture({ onReady }: { onReady: () => void }) {
  const logo = useLoader(FileLoader, "/logo-mark.svg") as string;
  const geometry = useMemo(() => {
    // Extrude the existing brand paths; gradient fills are irrelevant to the
    // physical material. Omit the fourth, flat highlight path in the source SVG.
    const parsed = new SVGLoader().parse(logo.replace(/url\(#[^)]+\)/g, "#e7c78a"));
    return parsed.paths.slice(0, 3).flatMap(path => SVGLoader.createShapes(path)).map(shape => {
      const result = new ExtrudeGeometry(shape, { depth: 5, bevelEnabled: true, bevelSegments: 3, steps: 1, bevelSize: 0.5, bevelThickness: 0.5, curveSegments: 12 });
      result.translate(-35, -30, -2.5);
      return result;
    });
  }, [logo]);
  const emblem = useRef<Group>(null);
  const orbit = useRef<Group>(null);
  const ready = useRef(false);
  useEffect(() => () => geometry.forEach(item => item.dispose()), [geometry]);
  useFrame(({ clock, pointer }, delta) => {
    const t = clock.elapsedTime;
    if (emblem.current) {
      emblem.current.rotation.y = MathUtils.damp(emblem.current.rotation.y, -0.22 + Math.sin(t * 0.23) * 0.12 + pointer.x * 0.1, 3, delta);
      emblem.current.rotation.x = Math.sin(t * 0.2) * 0.04;
      emblem.current.position.y = Math.sin(t * 0.45) * 0.07;
    }
    if (orbit.current) orbit.current.rotation.z = t * 0.075;
    if (!ready.current) { ready.current = true; onReady(); }
  });
  return <>
    <group ref={emblem} rotation={[0, -0.22, -0.025]}><group scale={[0.043, -0.043, 0.043]}>{geometry.map((shape, i) => <mesh key={i} geometry={shape}><meshPhysicalMaterial color="#dcb36c" metalness={1} roughness={0.26} clearcoat={0.35} clearcoatRoughness={0.3}/></mesh>)}</group></group>
    <group rotation={[0.95, -0.25, -0.22]}><group ref={orbit}>
      <mesh><torusGeometry args={[2.12, 0.009, 8, 160]}/><meshStandardMaterial color="#d2ae6b" metalness={0.85} roughness={0.32}/></mesh>
      {Array.from({ length: 6 }, (_, i) => {
        const angle = i / 6 * Math.PI * 2;
        return <mesh key={i} position={[Math.cos(angle) * 2.12, Math.sin(angle) * 2.12, 0]}><sphereGeometry args={[i === 0 ? 0.072 : 0.045, 16, 12]}/><meshStandardMaterial color="#ffdda1" metalness={0.75} roughness={0.22} emissive="#a77428" emissiveIntensity={i === 0 ? 0.55 : 0.15}/></mesh>;
      })}
    </group></group>
    <mesh rotation={[0.45, 0.65, 0.1]}><torusGeometry args={[2.38, 0.004, 6, 160]}/><meshBasicMaterial color="#8d754e" transparent opacity={0.45}/></mesh>
    <mesh rotation={[1.15, 0.2, -0.6]}><torusGeometry args={[1.87, 0.004, 6, 128]}/><meshBasicMaterial color="#b89a62" transparent opacity={0.45}/></mesh>
  </>;
}

function ContextLoss({ onFailure }: { onFailure: () => void }) {
  const canvas = useThree(state => state.gl.domElement);
  useEffect(() => {
    const onLost = (event: Event) => { event.preventDefault(); onFailure(); };
    canvas.addEventListener("webglcontextlost", onLost);
    return () => canvas.removeEventListener("webglcontextlost", onLost);
  }, [canvas, onFailure]);
  return null;
}

export default function OrbitScene({ running, compact, onReady, onFailure }: { running: boolean; compact: boolean; onReady: () => void; onFailure: () => void }) {
  return <Canvas frameloop="never" dpr={compact ? 1 : [1, 1.5]} camera={{ position: [0, 0, 8.7], fov: 36 }} gl={{ alpha: true, antialias: !compact, powerPreference: "low-power", toneMapping: ACESFilmicToneMapping }} fallback={null}>
    <Suspense fallback={null}>
      <StudioLight/>
      <Sculpture onReady={onReady}/>
      <FrameDriver running={running}/>
      <ContextLoss onFailure={onFailure}/>
    </Suspense>
  </Canvas>;
}
