import { useState } from 'react';
import { Button } from '@/components/shadcn/button';
import { ScrollReveal } from '../../components/motion';
import { marketingContent } from '../content';
import { RequestAccessModal } from '../RequestAccessModal';

export function FinalCtaSection() {
  const [open, setOpen] = useState(false);
  const { cta } = marketingContent;

  return (
    <section className="bg-marketing-bg px-6 pb-24 pt-4 md:px-12">
      <ScrollReveal className="mx-auto max-w-6xl">
        <div className="relative overflow-hidden rounded-3xl bg-foreground px-8 py-16 text-center md:px-16 md:py-20">
          <div
            className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_60%_80%_at_50%_-10%,hsl(var(--primary)/0.35)_0%,transparent_65%)]"
            aria-hidden
          />
          <div className="relative mx-auto max-w-2xl">
            <p className="text-label-caps text-primary-foreground/60">{cta.eyebrow}</p>
            <h2 className="mt-3 font-display text-3xl font-bold text-primary-foreground md:text-4xl">
              {cta.title}
            </h2>
            <p className="mt-4 text-base leading-relaxed text-primary-foreground/75 md:text-lg">{cta.subtitle}</p>
            <div className="mt-8">
              <Button size="lg" className="px-10" onClick={() => setOpen(true)}>
                {cta.button}
              </Button>
            </div>
            <p className="mt-5 text-xs text-primary-foreground/55">{cta.note}</p>
          </div>
        </div>
      </ScrollReveal>
      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </section>
  );
}
