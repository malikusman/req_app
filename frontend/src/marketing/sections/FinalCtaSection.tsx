import { useState } from 'react';
import { Button } from '@/components/shadcn/button';
import { ScrollReveal } from '../../components/motion';
import { marketingContent } from '../content';
import { RequestAccessModal } from '../RequestAccessModal';

export function FinalCtaSection() {
  const [open, setOpen] = useState(false);
  const { cta } = marketingContent;

  return (
    <section className="relative overflow-hidden border-t border-marketing-border bg-marketing-bg px-6 py-20 text-center md:px-12 md:py-24">
      <div
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(34,211,238,0.12)_0%,transparent_60%)]"
        aria-hidden
      />
      <ScrollReveal className="relative mx-auto max-w-2xl">
        <p className="text-label-caps text-marketing-gold">Get started</p>
        <h2 className="mt-2 font-display text-3xl font-bold text-marketing-foreground md:text-4xl">
          {cta.title}
        </h2>
        <p className="mt-4 text-base leading-relaxed text-marketing-muted md:text-lg">{cta.subtitle}</p>
        <p className="mt-3 text-sm text-marketing-muted/80">{cta.note}</p>
        <div className="relative mt-8 inline-flex items-center justify-center">
          <span
            className="pointer-events-none absolute inset-0 rounded-md border border-marketing-accent/30 animate-cta-pulse"
            aria-hidden
          />
          <Button size="lg" className="relative gap-2 px-8" onClick={() => setOpen(true)}>
            {cta.button}
          </Button>
        </div>
      </ScrollReveal>
      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </section>
  );
}
