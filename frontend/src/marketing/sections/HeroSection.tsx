import { useState } from 'react';
import { Check } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { Button } from '../../components/ui/Button';
import { AnimatedGradientText, AnimatedNumber, BorderBeam, ScrollReveal } from '../../components/motion';
import { fadeUp, slideInRight, spring, staggerContainer, transition } from '../../lib/motion';
import { marketingContent } from '../content';
import { RequestAccessModal } from '../RequestAccessModal';

export function HeroSection() {
  const [modalOpen, setModalOpen] = useState(false);
  const reduced = useReducedMotion();
  const { hero } = marketingContent;

  return (
    <section className="relative overflow-hidden border-b border-white/[0.08] bg-sidebar px-6 py-20 text-text-inverse md:px-12 md:py-28">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.09] animate-grid-drift bg-[length:64px_64px] bg-[linear-gradient(rgba(255,255,255,0.07)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.07)_1px,transparent_1px)]"
        aria-hidden
      />
      <div className="relative mx-auto flex max-w-6xl flex-col items-center gap-12 lg:flex-row lg:items-center">
        <motion.div
          className="flex-1 text-center lg:text-left"
          initial={reduced ? false : 'hidden'}
          animate={reduced ? undefined : 'visible'}
          variants={staggerContainer(0.1)}
        >
          <motion.p
            variants={fadeUp}
            transition={transition.reveal}
            className="text-sm font-medium uppercase tracking-widest text-accent-muted"
          >
            {hero.eyebrow}
          </motion.p>
          <motion.h1
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-4 font-display text-7xl font-bold leading-none tracking-tight md:text-8xl"
          >
            Req
          </motion.h1>
          <motion.p
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-6 max-w-xl text-4xl font-bold leading-tight text-white md:text-5xl lg:text-6xl"
          >
            {hero.headline}{' '}
            <AnimatedGradientText className="text-4xl md:text-5xl lg:text-6xl">
              {hero.headlineAccent}
            </AnimatedGradientText>
            .
          </motion.p>
          <motion.p
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-5 max-w-xl text-base leading-relaxed text-gray-400 md:text-lg"
          >
            {hero.subhead}
          </motion.p>
          <motion.ul
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-6 max-w-xl space-y-2 text-left text-sm text-gray-300 md:text-base"
          >
            {hero.bullets.map((bullet) => (
              <li key={bullet} className="flex gap-2">
                <Check className="mt-0.5 h-4 w-4 shrink-0 text-accent" aria-hidden />
                <span>{bullet}</span>
              </li>
            ))}
          </motion.ul>
          <motion.div
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-8 flex flex-wrap justify-center gap-3 lg:justify-start"
          >
            <Button
              className="px-6 py-3 shadow-button-glow hover:shadow-button-glow"
              onClick={() => setModalOpen(true)}
            >
              {hero.primaryCta}
            </Button>
            <Button
              variant="ghost"
              className="border border-gray-600 px-6 py-3 text-text-inverse hover:bg-sidebar-hover"
              onClick={() => document.getElementById('how-it-works')?.scrollIntoView({ behavior: 'smooth' })}
            >
              {hero.secondaryCta}
            </Button>
          </motion.div>
        </motion.div>

        <ScrollReveal variant="slideInRight" className="relative w-full flex-1">
          <div
            className="pointer-events-none absolute left-1/2 top-1/2 h-[600px] w-[600px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,rgba(79,70,229,0.15)_0%,transparent_70%)]"
            aria-hidden
          />
          <motion.div
            className="relative overflow-hidden rounded-lg border border-[#2D2D3A] bg-sidebar-active shadow-hero-mockup"
            whileHover={reduced ? undefined : { y: -4 }}
            transition={spring.soft}
          >
            <BorderBeam duration={14} />
            <div className="relative flex items-center gap-3 border-b border-[#2D2D3A] px-4 py-2.5">
              <span className="h-3 w-3 rounded-full bg-red-500/90" />
              <span className="h-3 w-3 rounded-full bg-amber-400/90" />
              <span className="h-3 w-3 rounded-full bg-green-500/90" />
              <div className="ml-2 flex-1 rounded-md bg-black/30 px-3 py-1 text-xs text-gray-400">
                app.reqapp.com
              </div>
            </div>
            <div className="relative rounded-b bg-surface-muted p-6">
              <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">
                {hero.mockup.title}
              </p>
              <p className="mt-2 font-display text-3xl font-bold text-text-primary">
                <AnimatedNumber value={hero.mockup.readinessValue} suffix="%" />
              </p>
              <p className="text-sm text-text-secondary">{hero.mockup.readinessLabel}</p>
              <div className="mt-4 grid grid-cols-2 gap-3">
                {hero.mockup.stats.map((stat) => (
                  <div
                    key={stat.label}
                    className="rounded-card border border-border bg-surface p-3 shadow-card"
                  >
                    <p className="text-2xl font-semibold text-text-primary">
                      <AnimatedNumber value={stat.value} />
                    </p>
                    <p className="text-xs text-text-secondary">{stat.label}</p>
                  </div>
                ))}
              </div>
            </div>
          </motion.div>
        </ScrollReveal>
      </div>
      <RequestAccessModal open={modalOpen} onClose={() => setModalOpen(false)} />
    </section>
  );
}
