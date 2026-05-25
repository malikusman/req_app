import { useEffect, useMemo, useRef, useState } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { spring } from '../../lib/motion';

const VB_W = 1200;
const VB_H = 800;
const HUB_ID = 'hub';

export type DiscoveryInterview = {
  id: string;
  name: string;
  insight: string;
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

function initialsFromName(name: string) {
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return name.slice(0, 2).toUpperCase();
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

type GraphEdge = { id: string; d: string };

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
      out.push({ id: edgeId, d: `M ${from.x} ${from.y} L ${to.x} ${to.y}` });
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

export function HeroDiscoveryGraph({
  interviews,
  hub,
  whatsappAppearances = 2,
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
  const [waKey, setWaKey] = useState(0);
  const [showGlow, setShowGlow] = useState(reduced);
  const [graphOpacity, setGraphOpacity] = useState(1);

  const hubSvg = useMemo(() => pctToSvg(hub.x, hub.y), [hub.x, hub.y]);

  const edges = useMemo(
    () => buildEdgeList(interviews, hub, new Set([...pinnedNodes, HUB_ID]), visibleEdges),
    [interviews, hub, pinnedNodes, visibleEdges]
  );

  const whatsappPosition = useMemo(() => {
    const last = interviews[interviews.length - 1];
    if (!last) return { x: hub.x, y: hub.y - 10 };
    return { x: (last.x + hub.x) / 2, y: (last.y + hub.y) / 2 };
  }, [interviews, hub.x, hub.y]);

  useEffect(() => {
    if (reduced) return;

    cancelledRef.current = false;

    const run = async () => {
      while (!cancelledRef.current) {
        pinnedRef.current = new Set();
        setPinnedNodes(new Set());
        setVisibleEdges(new Set());
        setActiveBubble(null);
        setBubbleFading(false);
        setShowWhatsapp(false);
        setShowGlow(false);
        setGraphOpacity(1);

        for (const interview of interviews) {
          if (cancelledRef.current) return;

          setActiveBubble(interview);
          setBubbleFading(false);
          await sleep(2200);

          setBubbleFading(true);
          await sleep(650);
          setActiveBubble(null);
          setBubbleFading(false);

          pinnedRef.current.add(interview.id);
          setPinnedNodes(new Set(pinnedRef.current));
          await sleep(350);

          setVisibleEdges((prev) => {
            const next = new Set(prev);
            for (const targetId of interview.connectsTo) {
              if (targetId === HUB_ID || pinnedRef.current.has(targetId)) {
                next.add(`${interview.id}-${targetId}`);
              }
            }
            return next;
          });
          await sleep(900);
        }

        for (let p = 0; p < whatsappAppearances; p++) {
          if (cancelledRef.current) return;
          setWaKey((k) => k + 1);
          setShowWhatsapp(true);
          await sleep(1400);
          setShowWhatsapp(false);
          await sleep(500);
        }

        setShowGlow(true);
        await sleep(2200);
        setShowGlow(false);
        setGraphOpacity(0);
        await sleep(800);
        setGraphOpacity(1);
      }
    };

    run();
    return () => {
      cancelledRef.current = true;
    };
  }, [reduced, interviews, whatsappAppearances]);

  // Fix edge visibility with functional update tied to interview loop
  // The double setVisibleEdges above is buggy - let me fix in the loop only

  if (reduced) {
    const staticEdges = buildEdgeList(
      interviews,
      hub,
      new Set([...interviews.map((i) => i.id), HUB_ID]),
      allEdgeIds(interviews)
    );
    return (
      <div className={cn('pointer-events-none absolute inset-0 h-full w-full', className)} aria-hidden>
        <svg
          className="absolute inset-0 h-full w-full opacity-50"
          viewBox={`0 0 ${VB_W} ${VB_H}`}
          preserveAspectRatio="xMidYMid slice"
        >
          <defs>
            <linearGradient id="heroEdgeGradStatic" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.2" />
              <stop offset="100%" stopColor="#06b6d4" stopOpacity="0.5" />
            </linearGradient>
          </defs>
          {staticEdges.map((edge) => (
            <path
              key={edge.id}
              d={edge.d}
              fill="none"
              stroke="url(#heroEdgeGradStatic)"
              strokeWidth={1.2}
              strokeLinecap="round"
              opacity={0.55}
            />
          ))}
        </svg>
        {interviews.map((interview) => (
          <div
            key={interview.id}
            className="absolute z-10 flex h-8 w-8 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border border-marketing-accent/40 bg-marketing-surface-elevated/80 text-[10px] font-semibold text-marketing-foreground"
            style={{ left: `${interview.x}%`, top: `${interview.y}%` }}
          >
            {initialsFromName(interview.name)}
          </div>
        ))}
        <div
          className="absolute z-10 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-marketing-accent/60"
          style={{ left: `${hub.x}%`, top: `${hub.y}%` }}
        />
        <div
          className="absolute z-20 flex h-12 w-12 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-[#25D366] text-white shadow-lg"
          style={{ left: `${whatsappPosition.x}%`, top: `${whatsappPosition.y}%` }}
        >
          <WhatsAppIcon className="h-7 w-7" />
        </div>
      </div>
    );
  }

  return (
    <motion.div
      className={cn('pointer-events-none absolute inset-0 h-full w-full', className)}
      animate={{ opacity: graphOpacity }}
      transition={{ duration: 0.7 }}
      aria-hidden
    >
      <svg
        className="absolute inset-0 h-full w-full"
        viewBox={`0 0 ${VB_W} ${VB_H}`}
        preserveAspectRatio="xMidYMid slice"
      >
        <defs>
          <linearGradient id="heroEdgeGradAnim" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.15" />
            <stop offset="50%" stopColor="#22d3ee" stopOpacity="0.7" />
            <stop offset="100%" stopColor="#06b6d4" stopOpacity="0.25" />
          </linearGradient>
        </defs>
        <circle cx={hubSvg.x} cy={hubSvg.y} r={6} fill="#22d3ee" fillOpacity={0.35} />
        {showGlow && (
          <motion.circle
            cx={hubSvg.x}
            cy={hubSvg.y}
            r={80}
            fill="none"
            stroke="#22d3ee"
            strokeWidth={1}
            initial={{ opacity: 0 }}
            animate={{ opacity: [0.15, 0.45, 0.15], scale: [0.9, 1.15, 0.9] }}
            transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
          />
        )}
        {edges.map((edge, i) => (
          <motion.path
            key={edge.id}
            d={edge.d}
            fill="none"
            stroke="url(#heroEdgeGradAnim)"
            strokeWidth={1.2}
            strokeLinecap="round"
            initial={{ pathLength: 0, opacity: 0 }}
            animate={{ pathLength: 1, opacity: 0.65 }}
            transition={{
              pathLength: { duration: 0.5, delay: i * 0.04, ease: 'easeOut' },
              opacity: { duration: 0.25 },
            }}
          />
        ))}
      </svg>

      <AnimatePresence>
        {interviews
          .filter((i) => pinnedNodes.has(i.id))
          .map((interview) => (
            <motion.div
              key={interview.id}
              className="absolute z-10 flex -translate-x-1/2 -translate-y-1/2"
              style={{ left: `${interview.x}%`, top: `${interview.y}%` }}
              initial={{ opacity: 0, scale: 0.4 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={spring.soft}
            >
              <div className="flex h-8 w-8 items-center justify-center rounded-full border border-marketing-accent/50 bg-marketing-surface-elevated/90 text-[10px] font-semibold text-marketing-foreground shadow-md backdrop-blur-sm">
                {initialsFromName(interview.name)}
              </div>
            </motion.div>
          ))}
      </AnimatePresence>

      <AnimatePresence>
        {activeBubble && (
          <motion.div
            key={activeBubble.id}
            className="absolute z-30 max-w-[180px] -translate-x-1/2 sm:max-w-[200px] sm:min-w-[140px]"
            style={{ left: `${activeBubble.x}%`, top: `${activeBubble.y}%` }}
            initial={{ opacity: 0, scale: 0.85, y: 8 }}
            animate={
              bubbleFading
                ? { opacity: 0, scale: 0.9, y: -4 }
                : { opacity: 1, scale: 1, y: -12 }
            }
            exit={{ opacity: 0, scale: 0.85 }}
            transition={spring.soft}
          >
            <div className="rounded-lg border border-marketing-accent/40 bg-marketing-surface-elevated/95 px-3 py-2.5 shadow-lg backdrop-blur-md">
              <div className="flex items-center gap-2">
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-marketing-accent/20 text-[10px] font-bold text-marketing-accent">
                  {initialsFromName(activeBubble.name)}
                </span>
                <p className="text-xs font-semibold text-marketing-foreground">{activeBubble.name}</p>
              </div>
              <p className="mt-1.5 text-[11px] leading-snug text-marketing-muted">
                {activeBubble.insight}
              </p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {showWhatsapp && (
          <motion.div
            key={`wa-${waKey}`}
            className="absolute z-40 flex h-14 w-14 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-[#25D366] text-white shadow-xl ring-4 ring-[#25D366]/30"
            style={{ left: `${whatsappPosition.x}%`, top: `${whatsappPosition.y}%` }}
            initial={{ scale: 0, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.5, opacity: 0 }}
            transition={spring.soft}
          >
            <WhatsAppIcon className="h-8 w-8" />
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
