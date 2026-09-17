import { useState } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { MessageCircle, Sparkles } from 'lucide-react';
import { Button } from '@/components/shadcn/button';
import { marketingContent, type HeroChatMessage } from '../content';
import { RequestAccessModal } from '../RequestAccessModal';

/** Seconds between each chat element appearing in the hero conversation. */
const BEAT = 0.55;
/** Delay before the first bubble lands. */
const LEAD_IN = 0.35;

function HeroChatBubble({ message, index }: { message: HeroChatMessage; index: number }) {
  const reduced = useReducedMotion();
  const fromAgent = message.from === 'agent';

  return (
    <motion.div
      className={fromAgent ? 'flex justify-start' : 'flex justify-end'}
      initial={reduced ? false : { opacity: 0, y: 14, scale: 0.96 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ delay: reduced ? 0 : LEAD_IN + index * BEAT, type: 'spring', stiffness: 320, damping: 26 }}
    >
      <p
        className={
          fromAgent
            ? 'm-0 max-w-[85%] rounded-2xl rounded-bl-md bg-marketing-surface px-4 py-2.5 text-sm leading-relaxed text-marketing-foreground shadow-card'
            : 'm-0 max-w-[85%] rounded-2xl rounded-br-md bg-marketing-accent-muted px-4 py-2.5 text-sm leading-relaxed text-marketing-foreground shadow-card'
        }
      >
        {message.text}
      </p>
    </motion.div>
  );
}

/**
 * One of only two elevated elements on the page. Everything else is a hairline,
 * so the shadow here is doing real work rather than decorating.
 */
function HeroChatCard() {
  const reduced = useReducedMotion();
  const { chat } = marketingContent.hero;
  const insightDelay = LEAD_IN + chat.messages.length * BEAT + 0.3;

  return (
    <div className="relative mx-auto w-full max-w-md">
      <div
        className="pointer-events-none absolute -inset-8 rounded-[3rem] bg-marketing-accent/10 blur-2xl"
        aria-hidden
      />
      <div className="relative overflow-hidden rounded-3xl border border-marketing-border bg-marketing-surface-elevated shadow-hero-mockup">
        <div className="flex items-center gap-3 border-b border-marketing-border bg-marketing-surface px-5 py-3.5">
          <span className="flex h-9 w-9 items-center justify-center rounded-full bg-marketing-accent text-white">
            <MessageCircle className="h-4 w-4" aria-hidden />
          </span>
          <div>
            <p className="m-0 text-sm font-bold text-marketing-foreground">{chat.contactName}</p>
            <p className="m-0 text-xs text-marketing-accent">{chat.contactStatus}</p>
          </div>
        </div>

        <div className="flex flex-col gap-3 px-5 py-6" aria-label="Example Mjadi interview on WhatsApp">
          {chat.messages.map((message, i) => (
            <HeroChatBubble key={message.text} message={message} index={i} />
          ))}

          <motion.div
            className="mt-2 flex items-start gap-3 rounded-2xl border border-marketing-accent/25 bg-marketing-surface p-4"
            initial={reduced ? false : { opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: reduced ? 0 : insightDelay, type: 'spring', stiffness: 260, damping: 24 }}
          >
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-marketing-accent-muted">
              <Sparkles className="h-4 w-4 text-marketing-accent" aria-hidden />
            </span>
            <div>
              <p className="m-0 text-label-caps text-marketing-accent">{chat.insight.label}</p>
              <p className="m-0 mt-1 text-xs leading-relaxed text-marketing-muted">{chat.insight.text}</p>
            </div>
          </motion.div>
        </div>
      </div>
    </div>
  );
}

export function HeroSection() {
  const [modalOpen, setModalOpen] = useState(false);
  const reduced = useReducedMotion();
  const { hero } = marketingContent;

  return (
    <section className="relative overflow-hidden">
      <div
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_50%_60%_at_78%_20%,hsl(var(--primary)/0.08)_0%,transparent_70%)]"
        aria-hidden
      />
      <div className="relative mx-auto max-w-6xl px-5 pb-14 pt-14 sm:px-8 sm:pb-16 lg:pt-20">
        {/* Asymmetric: the headline is long, and an even split ran it to six lines. */}
        <div className="grid items-center gap-12 lg:grid-cols-[1.1fr_0.9fr] lg:gap-12">
          <motion.div
            initial={reduced ? false : { opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, ease: 'easeOut' }}
          >
            <p className="m-0 text-label-caps text-marketing-accent">{hero.eyebrow}</p>
            <h1 className="m-0 mt-4 text-balance font-display text-4xl font-extrabold leading-[1.06] tracking-tight text-marketing-foreground sm:text-5xl lg:text-[3.1rem]">
              {hero.headline} <span className="text-marketing-accent">{hero.headlineAccent}</span>
            </h1>
            <p className="m-0 mt-6 max-w-xl text-pretty text-lg leading-relaxed text-marketing-muted">
              {hero.subhead}
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <Button size="lg" className="px-8" onClick={() => setModalOpen(true)}>
                {hero.primaryCta}
              </Button>
              <Button
                size="lg"
                variant="outline"
                onClick={() => document.getElementById('how-it-works')?.scrollIntoView({ behavior: 'smooth' })}
              >
                {hero.secondaryCta}
              </Button>
            </div>

            <dl className="mt-10 grid max-w-xl grid-cols-1 gap-5 border-t border-marketing-border pt-8 sm:grid-cols-3 sm:gap-6">
              {hero.stats.map((stat) => (
                <div key={stat.label}>
                  <dt className="sr-only">{stat.label}</dt>
                  <dd className="m-0 font-display text-2xl font-bold tabular-nums text-marketing-foreground">
                    {stat.value}
                  </dd>
                  <p className="m-0 mt-1 text-xs leading-snug text-marketing-muted">{stat.label}</p>
                </div>
              ))}
            </dl>
          </motion.div>

          <HeroChatCard />
        </div>

        {/*
          The industry list was a full band of its own with a scrolling marquee.
          It is one line of context, so it sits at the foot of the hero now —
          one fewer section boundary, and it reads as a qualifier on the claim
          above rather than as a (non-existent) client logo wall.
        */}
        <div className="mt-14 flex flex-col gap-3 border-t border-marketing-border pt-7 sm:flex-row sm:items-baseline sm:gap-6">
          <p className="m-0 shrink-0 text-label-caps text-marketing-muted">{hero.industriesLabel}</p>
          <ul className="m-0 flex list-none flex-wrap gap-x-5 gap-y-1.5 p-0">
            {hero.industries.map((industry) => (
              <li key={industry} className="text-sm font-medium text-marketing-foreground/70">
                {industry}
              </li>
            ))}
          </ul>
        </div>
      </div>
      <RequestAccessModal open={modalOpen} onClose={() => setModalOpen(false)} />
    </section>
  );
}
