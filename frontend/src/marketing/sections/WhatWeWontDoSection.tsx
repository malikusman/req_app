import { X } from 'lucide-react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

/** Confidence as differentiation. A new firm can say this; a large one usually will not. */
export function WhatWeWontDoSection() {
  const { whatWeWontDo } = marketingContent;

  return (
    <section className="bg-marketing-surface-elevated py-20 sm:py-28">
      <div className="mx-auto max-w-4xl px-5 sm:px-8">
        <ScrollReveal>
          <p className="m-0 text-label-caps text-marketing-accent">{whatWeWontDo.eyebrow}</p>
          <h2 className="m-0 mt-3 text-balance text-3xl font-semibold tracking-tight text-marketing-foreground sm:text-4xl">
            {whatWeWontDo.title}
          </h2>
        </ScrollReveal>

        <Stagger className="mt-8 grid gap-3 sm:grid-cols-2">
          {whatWeWontDo.items.map((item) => (
            <div
              key={item}
              className="flex items-start gap-3 rounded-2xl bg-marketing-surface p-5 shadow-marketing-card"
            >
              <X className="mt-0.5 h-4 w-4 shrink-0 text-marketing-accent" aria-hidden="true" />
              <p className="m-0 text-base leading-relaxed text-marketing-muted">{item}</p>
            </div>
          ))}
        </Stagger>
      </div>
    </section>
  );
}
