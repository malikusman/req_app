import { useState } from 'react';
import { Button } from '../../components/ui/Button';
import { ScrollReveal } from '../../components/motion';
import { marketingContent } from '../content';
import { RequestAccessModal } from '../RequestAccessModal';

export function FinalCtaSection() {
  const [open, setOpen] = useState(false);
  const { cta } = marketingContent;

  return (
    <section className="bg-sidebar px-6 py-20 text-center text-text-inverse md:px-12 md:py-24">
      <ScrollReveal className="mx-auto max-w-2xl">
        <h2 className="font-display text-3xl font-bold md:text-4xl">{cta.title}</h2>
        <p className="mt-4 text-base leading-relaxed text-gray-400 md:text-lg">{cta.subtitle}</p>
        <p className="mt-3 text-sm text-gray-500">{cta.note}</p>
        <div className="relative mt-8 inline-flex items-center justify-center">
          <span
            className="pointer-events-none absolute inset-0 rounded-button border border-accent/20 animate-cta-pulse"
            aria-hidden
          />
          <span
            className="pointer-events-none absolute inset-0 rounded-button border border-accent/20 animate-cta-pulse-delayed"
            aria-hidden
          />
          <Button className="relative px-8 py-4 text-lg shadow-button-glow" onClick={() => setOpen(true)}>
            {cta.button}
          </Button>
        </div>
      </ScrollReveal>
      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </section>
  );
}
