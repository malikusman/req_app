import { useState } from 'react';
import { MarketingAnimatedHero } from '@/components/shadcn/animated-hero';
import { HeroDiscoveryGraph, HeroOrb } from '../../components/motion';
import { marketingContent } from '../content';
import { RequestAccessModal } from '../RequestAccessModal';

export function HeroSection() {
  const [modalOpen, setModalOpen] = useState(false);
  const { hero } = marketingContent;
  const { discoveryGraph } = hero;

  return (
    <section
      className="relative min-h-[88vh] overflow-hidden border-b border-marketing-border"
      aria-label={discoveryGraph.ariaLabel}
    >
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.06] animate-grid-drift bg-[length:64px_64px] bg-[linear-gradient(rgba(255,255,255,0.06)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.06)_1px,transparent_1px)]"
        aria-hidden
      />
      <HeroDiscoveryGraph
        interviews={discoveryGraph.interviews}
        hub={discoveryGraph.hub}
        whatsappAppearances={discoveryGraph.whatsappAppearances}
        loopResetMs={discoveryGraph.loopResetMs}
        className="z-0 opacity-[0.52]"
      />
      <div
        className="pointer-events-none absolute inset-0 z-[1] bg-[radial-gradient(ellipse_68%_58%_at_50%_44%,rgba(5,5,8,0.9)_0%,rgba(5,5,8,0.45)_48%,transparent_78%)] sm:bg-[radial-gradient(ellipse_62%_52%_at_50%_42%,rgba(5,5,8,0.88)_0%,rgba(5,5,8,0.4)_52%,transparent_80%)]"
        aria-hidden
      />
      <HeroOrb className="z-[1] opacity-25" />
      <div className="relative z-10">
        <MarketingAnimatedHero
          variant="overlay"
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
        />
      </div>
      <RequestAccessModal open={modalOpen} onClose={() => setModalOpen(false)} />
    </section>
  );
}
