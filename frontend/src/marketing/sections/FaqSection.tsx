import { useState } from 'react';
import { ChevronDown } from 'lucide-react';
import { ScrollReveal } from '../../components/motion';
import { cn } from '../../lib/cn';
import { marketingContent } from '../content';

export function FaqSection() {
  const { faq } = marketingContent;
  const [openIndex, setOpenIndex] = useState<number | null>(0);

  return (
    <section id="faq" className="border-t border-marketing-border bg-marketing-surface px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-3xl">
        <ScrollReveal>
          <p className="text-center text-label-caps text-marketing-gold">FAQ</p>
          <h2 className="mt-2 text-center font-display text-page-title text-marketing-foreground">
            {faq.title}
          </h2>
        </ScrollReveal>
        <ul className="mt-10 space-y-3">
          {faq.items.map((item, i) => {
            const open = openIndex === i;
            return (
              <li
                key={item.q}
                className="overflow-hidden rounded-card border border-marketing-border bg-marketing-bg/50"
              >
                <button
                  type="button"
                  className="flex w-full items-center justify-between gap-4 px-5 py-4 text-left"
                  onClick={() => setOpenIndex(open ? null : i)}
                  aria-expanded={open}
                >
                  <span className="font-medium text-marketing-foreground">{item.q}</span>
                  <ChevronDown
                    className={cn(
                      'h-5 w-5 shrink-0 text-marketing-muted transition-transform',
                      open && 'rotate-180'
                    )}
                    aria-hidden
                  />
                </button>
                {open && (
                  <p className="border-t border-marketing-border px-5 pb-4 pt-2 text-sm leading-relaxed text-marketing-muted">
                    {item.a}
                  </p>
                )}
              </li>
            );
          })}
        </ul>
      </div>
    </section>
  );
}
