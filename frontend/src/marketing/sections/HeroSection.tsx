import { useState } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { MarketingAnimatedHero } from '@/components/shadcn/animated-hero';
import { AnimatedNumber, BorderBeam, HeroOrb, ScrollReveal } from '../../components/motion';
import { spring } from '../../lib/motion';
import { marketingContent } from '../content';
import { RequestAccessModal } from '../RequestAccessModal';

function HeroMockup() {
  const reduced = useReducedMotion();
  const { mockup } = marketingContent.hero;

  return (
    <ScrollReveal variant="slideInRight" className="relative w-full">
      <motion.div
        className="relative overflow-hidden rounded-lg border border-marketing-border bg-marketing-surface-elevated shadow-marketing-card"
        whileHover={reduced ? undefined : { y: -4 }}
        transition={spring.soft}
      >
        <BorderBeam duration={14} colorFrom="#22d3ee" colorTo="#06b6d4" />
        <div className="relative flex items-center gap-3 border-b border-marketing-border px-4 py-2.5">
          <span className="h-3 w-3 rounded-full bg-red-500/90" />
          <span className="h-3 w-3 rounded-full bg-amber-400/90" />
          <span className="h-3 w-3 rounded-full bg-green-500/90" />
          <div className="ml-2 flex-1 rounded-md bg-black/40 px-3 py-1 text-xs text-marketing-muted">
            app.reqapp.com
          </div>
        </div>
        <div className="relative rounded-b bg-marketing-surface p-6">
          <p className="text-xs font-semibold uppercase tracking-wide text-marketing-muted">
            {mockup.title}
          </p>
          <p className="mt-2 font-display text-3xl font-bold text-marketing-foreground">
            <AnimatedNumber value={mockup.readinessValue} suffix="%" />
          </p>
          <p className="text-sm text-marketing-muted">{mockup.readinessLabel}</p>
          <div className="mt-4 grid grid-cols-2 gap-3">
            {mockup.stats.map((stat) => (
              <div
                key={stat.label}
                className="rounded-card border border-marketing-border bg-marketing-bg p-3"
              >
                <p className="text-2xl font-semibold text-marketing-foreground">
                  <AnimatedNumber value={stat.value} />
                </p>
                <p className="text-xs text-marketing-muted">{stat.label}</p>
              </div>
            ))}
          </div>
        </div>
      </motion.div>
    </ScrollReveal>
  );
}

export function HeroSection() {
  const [modalOpen, setModalOpen] = useState(false);
  const { hero } = marketingContent;

  return (
    <section className="relative overflow-hidden border-b border-marketing-border">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.06] animate-grid-drift bg-[length:64px_64px] bg-[linear-gradient(rgba(255,255,255,0.06)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.06)_1px,transparent_1px)]"
        aria-hidden
      />
      <HeroOrb />
      <MarketingAnimatedHero
        eyebrow={hero.eyebrow}
        headlinePrefix={hero.headlinePrefix}
        rotatingWords={[...hero.rotatingWords]}
        subhead={hero.subhead}
        primaryCta={{
          label: hero.primaryCta,
          onClick: () => setModalOpen(true),
        }}
        secondaryCta={{
          label: hero.secondaryCta,
          onClick: () => document.getElementById('how-it-works')?.scrollIntoView({ behavior: 'smooth' }),
        }}
        rightSlot={<HeroMockup />}
      />
      <RequestAccessModal open={modalOpen} onClose={() => setModalOpen(false)} />
    </section>
  );
}
