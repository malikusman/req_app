import { useEffect, useMemo, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';

const VB_W = 1200;
const VB_H = 800;

const BUBBLE_VISIBLE_MS = 1500;
const BUBBLE_FADE_MS = 550;
const EDGE_DRAW_MS = 1800;
const WA_HOLD_MS = 1000;
const WA_FADE_MS = 600;
const HUB_ID = 'hub';

const EDGE_STROKE_PEER = 'rgba(255, 255, 255, 0.22)';
const EDGE_STROKE_KB = 'rgba(34, 211, 238, 0.32)';

/** Peripheral anchors for random WhatsApp pulses (outside headline safe zone). */
const WHATSAPP_ANCHORS = [
  { x: 86, y: 22 },
  { x: 10, y: 28 },
  { x: 92, y: 55 },
  { x: 8, y: 62 },
  { x: 84, y: 85 },
  { x: 16, y: 88 },
  { x: 72, y: 14 },
  { x: 22, y: 16 },
] as const;

export type DiscoveryInterview = {
  id: string;
  name: string;
  /** Shown in bubble; defaults to first name from `name`. */
  displayName?: string;
  snippet: string;
  /** Text direction for snippet (e.g. Arabic). */
  dir?: 'rtl' | 'ltr';
  x: number;
  y: number;
  connectsTo: string[];
};

export type HeroDiscoveryGraphProps = {
  interviews: DiscoveryInterview[];
  hub: { id: string; x: number; y: number };
  whatsappAppearances?: number;
  loopResetMs?: number;
  className?: string;
};

function pctToSvg(x: number, y: number) {
  return { x: (x / 100) * VB_W, y: (y / 100) * VB_H };
}

function firstNameFrom(fullName: string) {
  return fullName.trim().split(/\s+/)[0] ?? fullName;
}

function pickRandomAnchor(exclude?: { x: number; y: number }) {
  const pool = WHATSAPP_ANCHORS.filter(
    (a) => !exclude || a.x !== exclude.x || a.y !== exclude.y
  );
  return pool[Math.floor(Math.random() * pool.length)] ?? WHATSAPP_ANCHORS[0];
}

function wavePath(
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  edgeId: string
): string {
  const mx = (x1 + x2) / 2;
  const my = (y1 + y2) / 2;
  const dx = x2 - x1;
  const dy = y2 - y1;
  const len = Math.hypot(dx, dy) || 1;
  const bend = len * 0.14 * (edgeId.split('').reduce((s, c) => s + c.charCodeAt(0), 0) % 2 === 0 ? 1 : -1);
  const cx = mx + (-dy / len) * bend;
  const cy = my + (dx / len) * bend;
  return `M ${x1} ${y1} Q ${cx} ${cy} ${x2} ${y2}`;
}

function WhatsAppIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden>
      <path
        fill="currentColor"
        d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"
      />
    </svg>
  );
}

type GraphEdge = { id: string; d: string; toHub: boolean };

function buildEdgeList(
  interviews: DiscoveryInterview[],
  hub: { id: string; x: number; y: number },
  pinnedIds: Set<string>,
  edgeIds: Set<string>
): GraphEdge[] {
  const pos = new Map<string, { x: number; y: number }>();
  pos.set(hub.id, { x: hub.x, y: hub.y });
  for (const i of interviews) {
    if (pinnedIds.has(i.id)) pos.set(i.id, { x: i.x, y: i.y });
  }

  const out: GraphEdge[] = [];
  for (const interview of interviews) {
    if (!pinnedIds.has(interview.id)) continue;
    for (const targetId of interview.connectsTo) {
      const edgeId = `${interview.id}-${targetId}`;
      if (!edgeIds.has(edgeId)) continue;
      const target = pos.get(targetId);
      if (!target) continue;
      const from = pctToSvg(interview.x, interview.y);
      const to = pctToSvg(target.x, target.y);
      out.push({
        id: edgeId,
        d: wavePath(from.x, from.y, to.x, to.y, edgeId),
        toHub: targetId === HUB_ID,
      });
    }
  }
  return out;
}

function allEdgeIds(interviews: DiscoveryInterview[]): Set<string> {
  const ids = new Set<string>();
  for (const i of interviews) {
    for (const t of i.connectsTo) ids.add(`${i.id}-${t}`);
  }
  return ids;
}

function sleep(ms: number) {
  return new Promise<void>((resolve) => window.setTimeout(resolve, ms));
}

function AmbientEdge({
  edge,
  index,
  animateDraw,
}: {
  edge: GraphEdge;
  index: number;
  animateDraw: boolean;
}) {
  const stroke = edge.toHub ? EDGE_STROKE_KB : EDGE_STROKE_PEER;
  const targetOpacity = edge.toHub ? 0.55 : 0.42;

  return (
    <motion.path
      d={edge.d}
      fill="none"
      stroke={stroke}
      strokeWidth={edge.toHub ? 1 : 0.85}
      strokeLinecap="round"
      strokeDasharray="4 8"
      initial={{ pathLength: 0, opacity: 0 }}
      animate={{
        pathLength: 1,
        opacity: animateDraw ? targetOpacity : targetOpacity * 0.85,
        strokeDashoffset: [0, -24],
      }}
      transition={{
        pathLength: { duration: 1.8, delay: index * 0.06, ease: 'easeInOut' },
        opacity: { duration: 0.9 },
        strokeDashoffset: { duration: 22, repeat: Infinity, ease: 'linear' },
      }}
    />
  );
}

function StaticAmbientEdge({ edge }: { edge: GraphEdge }) {
  return (
    <path
      d={edge.d}
      fill="none"
      stroke={edge.toHub ? EDGE_STROKE_KB : EDGE_STROKE_PEER}
      strokeWidth={0.85}
      strokeLinecap="round"
      strokeDasharray="4 8"
      opacity={edge.toHub ? 0.4 : 0.3}
    />
  );
}

function GraphHub({
  hub,
  hubSvg,
  pulse,
}: {
  hub: { x: number; y: number };
  hubSvg: { x: number; y: number };
  pulse: boolean;
}) {
  return (
    <>
      <motion.circle
        cx={hubSvg.x}
        cy={hubSvg.y}
        fill="none"
        stroke="rgba(34, 211, 238, 0.25)"
        strokeWidth={1}
        initial={{ r: 28, opacity: 0.2 }}
        animate={
          pulse
            ? { r: [28, 40, 28], opacity: [0.25, 0.5, 0.25] }
            : { r: 28, opacity: 0.2 }
        }
        transition={{ duration: 1.2, ease: 'easeInOut' }}
      />
      <circle cx={hubSvg.x} cy={hubSvg.y} r={5} fill="rgba(34, 211, 238, 0.45)" />
      <div
        className="absolute z-20 flex -translate-x-1/2 -translate-y-1/2 items-center justify-center"
        style={{ left: `${hub.x}%`, top: `${hub.y}%` }}
      >
        <div className="h-3 w-3 rounded-full bg-marketing-accent/50 ring-4 ring-marketing-accent/15" />
      </div>
    </>
  );
}

function bubbleDisplayName(interview: DiscoveryInterview) {
  return interview.displayName ?? firstNameFrom(interview.name);
}

export function HeroDiscoveryGraph({
  interviews,
  hub,
  whatsappAppearances = 1,
  className,
}: HeroDiscoveryGraphProps) {
  const reduced = useReducedMotion();
  const cancelledRef = useRef(false);
  const pinnedRef = useRef<Set<string>>(new Set());

  const [pinnedNodes, setPinnedNodes] = useState<Set<string>>(
    () => new Set(reduced ? interviews.map((i) => i.id) : [])
  );
  const [visibleEdges, setVisibleEdges] = useState<Set<string>>(
    () => (reduced ? allEdgeIds(interviews) : new Set())
  );
  const [activeBubble, setActiveBubble] = useState<DiscoveryInterview | null>(null);
  const [bubbleFading, setBubbleFading] = useState(false);
  const [showWhatsapp, setShowWhatsapp] = useState(false);
  const [waExiting, setWaExiting] = useState(false);
  const [waPosition, setWaPosition] = useState(WHATSAPP_ANCHORS[0]);
  const [waKey, setWaKey] = useState(0);
  const [graphOpacity, setGraphOpacity] = useState(1);
  const [newlyDrawnEdges, setNewlyDrawnEdges] = useState<Set<string>>(new Set());
  const [hubPulse, setHubPulse] = useState(false);

  const hubSvg = useMemo(() => pctToSvg(hub.x, hub.y), [hub.x, hub.y]);

  const edges = useMemo(
    () => buildEdgeList(interviews, hub, new Set([...pinnedNodes, HUB_ID]), visibleEdges),
    [interviews, hub, pinnedNodes, visibleEdges]
  );

  useEffect(() => {
    if (reduced) return;

    cancelledRef.current = false;

    const run = async () => {
      while (!cancelledRef.current) {
        pinnedRef.current = new Set();
        setPinnedNodes(new Set());
        setVisibleEdges(new Set());
        setNewlyDrawnEdges(new Set());
        setActiveBubble(null);
        setBubbleFading(false);
        setShowWhatsapp(false);
        setWaExiting(false);
        setGraphOpacity(1);
        setHubPulse(false);

        for (const interview of interviews) {
          if (cancelledRef.current) return;

          setActiveBubble(interview);
          setBubbleFading(false);
          await sleep(BUBBLE_VISIBLE_MS);

          setBubbleFading(true);
          await sleep(BUBBLE_FADE_MS);
          setActiveBubble(null);
          setBubbleFading(false);

          pinnedRef.current.add(interview.id);
          setPinnedNodes(new Set(pinnedRef.current));
          await sleep(280);

          const added = new Set<string>();
          for (const targetId of interview.connectsTo) {
            if (targetId === HUB_ID || pinnedRef.current.has(targetId)) {
              added.add(`${interview.id}-${targetId}`);
            }
          }
          const flowsToHub = interview.connectsTo.includes(HUB_ID);
          setVisibleEdges((prev) => new Set([...prev, ...added]));
          setNewlyDrawnEdges(added);
          if (flowsToHub) setHubPulse(true);
          await sleep(EDGE_DRAW_MS);
          setNewlyDrawnEdges(new Set());
          if (flowsToHub) {
            await sleep(400);
            setHubPulse(false);
          }
        }

        for (let p = 0; p < whatsappAppearances; p++) {
          if (cancelledRef.current) return;
          setWaKey((k) => k + 1);
          setWaPosition(pickRandomAnchor());
          setWaExiting(false);
          setShowWhatsapp(true);
          await sleep(WA_HOLD_MS);
          setWaExiting(true);
          await sleep(WA_FADE_MS);
          setShowWhatsapp(false);
          setWaExiting(false);
          await sleep(400);
        }

        setGraphOpacity(0);
        await sleep(700);
        setGraphOpacity(1);
      }
    };

    run();
    return () => {
      cancelledRef.current = true;
    };
  }, [reduced, interviews, whatsappAppearances]);

  if (reduced) {
    const staticEdges = buildEdgeList(
      interviews,
      hub,
      new Set([...interviews.map((i) => i.id), HUB_ID]),
      allEdgeIds(interviews)
    );
    const staticWa = WHATSAPP_ANCHORS[2];
    return (
      <div className={cn('pointer-events-none absolute inset-0 h-full w-full', className)} aria-hidden>
        <svg
          className="absolute inset-0 h-full w-full"
          viewBox={`0 0 ${VB_W} ${VB_H}`}
          preserveAspectRatio="xMidYMid slice"
        >
          {staticEdges.map((edge) => (
            <StaticAmbientEdge key={edge.id} edge={edge} />
          ))}
        </svg>
        <GraphHub hub={hub} hubSvg={hubSvg} pulse={false} />
        {interviews.map((interview) => (
          <div
            key={interview.id}
            className="absolute z-10 h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-marketing-accent/40 ring-2 ring-marketing-accent/15"
            style={{ left: `${interview.x}%`, top: `${interview.y}%` }}
          />
        ))}
        <div
          className="absolute z-10 flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-white/[0.08] ring-1 ring-white/15"
          style={{ left: `${staticWa.x}%`, top: `${staticWa.y}%` }}
        >
          <WhatsAppIcon className="h-6 w-6 text-white/45" />
        </div>
      </div>
    );
  }

  return (
    <motion.div
      className={cn('pointer-events-none absolute inset-0 h-full w-full', className)}
      animate={{ opacity: graphOpacity }}
      transition={{ duration: 0.65 }}
      aria-hidden
    >
      <svg
        className="absolute inset-0 h-full w-full"
        viewBox={`0 0 ${VB_W} ${VB_H}`}
        preserveAspectRatio="xMidYMid slice"
      >
        {edges.map((edge, i) => (
          <AmbientEdge
            key={edge.id}
            edge={edge}
            index={i}
            animateDraw={newlyDrawnEdges.has(edge.id)}
          />
        ))}
      </svg>

      <GraphHub hub={hub} hubSvg={hubSvg} pulse={hubPulse} />

      <AnimatePresence>
        {interviews
          .filter((i) => pinnedNodes.has(i.id))
          .map((interview) => (
            <motion.div
              key={interview.id}
              className="absolute z-10 -translate-x-1/2 -translate-y-1/2"
              style={{ left: `${interview.x}%`, top: `${interview.y}%` }}
              initial={{ opacity: 0, scale: 0.5 }}
              animate={{ opacity: 0.55, scale: 1 }}
              transition={{ duration: 0.5, ease: 'easeOut' }}
            >
              <div className="h-2 w-2 rounded-full bg-marketing-accent/50 ring-2 ring-marketing-accent/20" />
            </motion.div>
          ))}
      </AnimatePresence>

      <AnimatePresence>
        {activeBubble && (
          <motion.div
            key={activeBubble.id}
            className="absolute z-30 -translate-x-1/2"
            style={{ left: `${activeBubble.x}%`, top: `${activeBubble.y}%` }}
            initial={{ opacity: 0, scale: 0.96, y: 6 }}
            animate={
              bubbleFading
                ? { opacity: 0, scale: 0.98, y: -8 }
                : { opacity: 1, scale: 1, y: -14 }
            }
            exit={{ opacity: 0, scale: 0.96 }}
            transition={{ duration: bubbleFading ? 0.55 : 0.5, ease: 'easeOut' }}
          >
            <div
              className={cn(
                'min-w-[220px] max-w-[300px] rounded-xl border border-white/15 bg-marketing-surface-elevated/40 px-4 py-3.5 shadow-sm backdrop-blur-md',
                activeBubble.dir === 'rtl' && 'text-right'
              )}
              dir={activeBubble.dir}
            >
              <p className="text-sm font-medium text-marketing-foreground/90">
                {bubbleDisplayName(activeBubble)}
              </p>
              <p
                className={cn(
                  'mt-1.5 line-clamp-2 text-xs italic leading-relaxed text-marketing-muted/75',
                  activeBubble.dir === 'rtl' && 'font-normal'
                )}
              >
                {activeBubble.snippet}
              </p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {showWhatsapp && (
          <motion.div
            key={`wa-${waKey}`}
            className="absolute z-40 flex h-14 w-14 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-white/[0.1] ring-1 ring-white/20"
            style={{
              left: `${waPosition.x}%`,
              top: `${waPosition.y}%`,
              transformPerspective: 800,
            }}
            initial={{ opacity: 0, scale: 0.7, rotateY: 0 }}
            animate={
              waExiting
                ? { opacity: 0, scale: 0.85, rotateY: -18 }
                : { opacity: 0.65, scale: 1.12, rotateY: 0 }
            }
            exit={{ opacity: 0, scale: 0.7, rotateY: -18 }}
            transition={{ duration: waExiting ? 0.55 : 0.45, ease: 'easeOut' }}
          >
            <WhatsAppIcon className="h-9 w-9 text-white/55" />
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
