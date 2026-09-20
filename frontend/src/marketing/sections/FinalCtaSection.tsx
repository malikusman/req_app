import { useState } from 'react';
import { Button } from '@/components/shadcn/button';
import { ScrollReveal } from '../../components/motion';
import { marketingContent } from '../content';
import { RequestAccessModal } from '../RequestAccessModal';

/**
 * The single dark moment on the page, and the last thing on it. It closes the
 * document rather than competing with anything above it.
 */
export function FinalCtaSection() {
  const [open, setOpen] = useState(false);
  const { cta } = marketingContent;

  return (
    <section className="bg-marketing-bg px-5 pb-16 pt-4 sm:px-8 sm:pb-20">
      <ScrollReveal className="mx-auto max-w-5xl">
        <div className="relative overflow-hidden rounded-3xl bg-foreground px-6 py-14 text-center sm:px-12 sm:py-16">
          <div
            className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_60%_80%_at_50%_-10%,hsl(var(--primary)/0.35)_0%,transparent_65%)]"
            aria-hidden
          />
          <div className="relative mx-auto max-w-2xl">
            <p className="m-0 text-label-caps text-primary-foreground/60">{cta.eyebrow}</p>
            <h2 className="m-0 mt-3 text-balance font-display text-3xl font-bold leading-tight text-primary-foreground sm:text-4xl">
              {cta.title}
            </h2>
            <p className="m-0 mt-4 text-pretty text-base leading-relaxed text-primary-foreground/75">
              {cta.subtitle}
            </p>
            <div className="mt-8">
              <Button size="lg" className="px-10" onClick={() => setOpen(true)}>
                {cta.button}
              </Button>
            </div>
            <p className="m-0 mt-5 text-xs leading-relaxed text-primary-foreground/55">{cta.note}</p>
          </div>
        </div>
      </ScrollReveal>
      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </section>
  );
}
