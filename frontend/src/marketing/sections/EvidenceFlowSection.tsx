import { motion, useReducedMotion } from 'motion/react';
import {
  FileText,
  MessageCircle,
  Mic,
  Image as ImageIcon,
  ArrowDown,
  Waypoints,
  type LucideIcon,
} from 'lucide-react';
import { ScrollReveal } from '../../components/motion';
import { marketingContent } from '../content';

const inputIcons: Record<string, LucideIcon> = {
  document: FileText,
  chat: MessageCircle,
  voice: Mic,
  image: ImageIcon,
};

/** Horizontal connector with evidence "pulses" travelling along it (desktop only). */
function FlowConnector({ delay = 0 }: { delay?: number }) {
  const reduced = useReducedMotion();

  return (
    <div className="relative hidden h-full min-h-[3rem] items-center lg:flex" aria-hidden>
      <div className="h-px w-full bg-gradient-to-r from-marketing-border via-marketing-accent/40 to-marketing-border" />
      {!reduced && (
        <>
          {[0, 1].map((i) => (
            <motion.span
              key={i}
              className="absolute top-1/2 h-1.5 w-1.5 -translate-y-1/2 rounded-full bg-marketing-accent shadow-[0_0_8px_hsl(var(--primary)/0.55)]"
              initial={{ left: '0%', opacity: 0 }}
              animate={{ left: ['0%', '100%'], opacity: [0, 1, 1, 0] }}
              transition={{
                duration: 2.4,
                delay: delay + i * 1.2,
                repeat: Infinity,
                ease: 'linear',
              }}
            />
          ))}
        </>
      )}
    </div>
  );
}

function MobileArrow() {
  return (
    <div className="flex justify-center py-1 lg:hidden" aria-hidden>
      <ArrowDown className="h-5 w-5 text-marketing-accent/60" />
    </div>
  );
}

export function EvidenceFlowSection() {
  const reduced = useReducedMotion();
  const { evidenceFlow } = marketingContent;

  return (
    <section className="border-y border-marketing-border bg-marketing-surface px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <p className="text-label-caps text-marketing-accent">{evidenceFlow.eyebrow}</p>
          <h2 className="mt-2 font-display text-page-title text-marketing-foreground">{evidenceFlow.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-marketing-muted">{evidenceFlow.subtitle}</p>
        </ScrollReveal>

        <ScrollReveal variant="fadeIn" delay={0.15}>
          <div className="mt-14 grid items-center gap-4 lg:grid-cols-[1fr_3.5rem_auto_3.5rem_1.15fr] lg:gap-0">
            {/* Inputs */}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-1">
              {evidenceFlow.inputs.map((input, i) => {
                const Icon = inputIcons[input.kind] ?? FileText;
                return (
                  <motion.div
                    key={input.title}
                    className="flex items-center gap-3 rounded-2xl border border-marketing-border bg-marketing-surface-elevated px-4 py-3 shadow-marketing-card"
                    initial={reduced ? false : { opacity: 0, x: -16 }}
                    whileInView={{ opacity: 1, x: 0 }}
                    viewport={{ once: true, margin: '-40px' }}
                    transition={{ delay: reduced ? 0 : i * 0.12, type: 'spring', stiffness: 280, damping: 26 }}
                  >
                    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-marketing-accent-muted">
                      <Icon className="h-4 w-4 text-marketing-accent" aria-hidden />
                    </span>
                    <div className="min-w-0">
                      <p className="m-0 truncate text-sm font-semibold text-marketing-foreground">{input.title}</p>
                      <p className="m-0 text-xs text-marketing-muted">{input.caption}</p>
                    </div>
                  </motion.div>
                );
              })}
            </div>

            <FlowConnector delay={0.2} />
            <MobileArrow />

            {/* Hub */}
            <div className="relative mx-auto">
              {!reduced && (
                <motion.div
                  className="absolute -inset-3 rounded-full bg-marketing-accent/15 blur-md"
                  animate={{ scale: [1, 1.12, 1], opacity: [0.5, 0.9, 0.5] }}
                  transition={{ duration: 3, repeat: Infinity, ease: 'easeInOut' }}
                  aria-hidden
                />
              )}
              <div className="relative flex h-36 w-36 flex-col items-center justify-center gap-1.5 rounded-full border border-marketing-accent/30 bg-marketing-surface-elevated text-center shadow-hero-mockup">
                <Waypoints className="h-6 w-6 text-marketing-accent" aria-hidden />
                <p className="m-0 px-3 font-display text-sm font-bold leading-tight text-marketing-foreground">
                  {evidenceFlow.hub.title}
                </p>
                <p className="m-0 px-4 text-[10px] leading-snug text-marketing-muted">{evidenceFlow.hub.caption}</p>
              </div>
            </div>

            <FlowConnector delay={0.8} />
            <MobileArrow />

            {/* Outputs */}
            <div className="flex flex-col gap-3">
              {evidenceFlow.outputs.map((output, i) => {
                const isReport = i === evidenceFlow.outputs.length - 1;
                return (
                  <motion.div
                    key={output.step}
                    className={
                      isReport
                        ? 'rounded-2xl border border-marketing-accent/40 bg-marketing-accent-muted px-5 py-4 shadow-marketing-card'
                        : 'rounded-2xl border border-marketing-border bg-marketing-surface-elevated px-5 py-4 shadow-marketing-card'
                    }
                    initial={reduced ? false : { opacity: 0, x: 16 }}
                    whileInView={{ opacity: 1, x: 0 }}
                    viewport={{ once: true, margin: '-40px' }}
                    transition={{ delay: reduced ? 0 : 0.3 + i * 0.18, type: 'spring', stiffness: 280, damping: 26 }}
                  >
                    <p className="m-0 text-label-caps text-marketing-accent">{output.step}</p>
                    <p className="m-0 mt-1 text-sm leading-relaxed text-marketing-foreground">{output.text}</p>
                  </motion.div>
                );
              })}
            </div>
          </div>
        </ScrollReveal>
      </div>
    </section>
  );
}
