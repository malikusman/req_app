import { motion, useReducedMotion } from 'motion/react';
import { Bot, BellRing, Layers, type LucideIcon } from 'lucide-react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

const icons: LucideIcon[] = [Bot, BellRing, Layers];

export function AlwaysOnSection() {
  const reduced = useReducedMotion();
  const { alwaysOn } = marketingContent;

  return (
    <section className="bg-marketing-bg px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <p className="text-label-caps text-marketing-accent">{alwaysOn.eyebrow}</p>
          <h2 className="mt-2 font-display text-page-title text-marketing-foreground">{alwaysOn.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-marketing-muted">{alwaysOn.subtitle}</p>
        </ScrollReveal>

        <Stagger className="mt-14 grid gap-5 md:grid-cols-3" staggerDelay={0.1}>
          {alwaysOn.items.map((item, i) => {
            const Icon = icons[i] ?? Bot;
            return (
              <article
                key={item.title}
                className="flex h-full flex-col rounded-2xl bg-marketing-surface p-6 shadow-marketing-card transition-shadow hover:shadow-hero-mockup"
              >
                <div className="flex items-center justify-between">
                  <span className="relative flex h-10 w-10 items-center justify-center rounded-xl bg-marketing-accent-muted">
                    <Icon className="h-5 w-5 text-marketing-accent" aria-hidden />
                    {i === 1 && !reduced && (
                      <motion.span
                        className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full bg-marketing-accent"
                        animate={{ scale: [1, 1.5, 1], opacity: [1, 0.4, 1] }}
                        transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
                        aria-hidden
                      />
                    )}
                  </span>
                  <span className="rounded-full bg-marketing-accent-muted px-3 py-1 text-[11px] font-semibold text-marketing-accent">
                    {item.badge}
                  </span>
                </div>
                <h3 className="mt-4 font-display text-section-title text-marketing-foreground">{item.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-marketing-muted">{item.body}</p>
              </article>
            );
          })}
        </Stagger>
      </div>
    </section>
  );
}
