import { Building2, ClipboardCheck, Settings2 } from 'lucide-react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

const icons = [Building2, ClipboardCheck, Settings2] as const;

export function PlatformSection() {
  const { platform } = marketingContent;

  return (
    <section id="platform" className="border-y border-marketing-border bg-marketing-surface px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <p className="text-label-caps text-marketing-accent">{platform.eyebrow}</p>
          <h2 className="mt-2 font-display text-page-title text-marketing-foreground">{platform.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-marketing-muted">{platform.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-6 lg:grid-cols-3" staggerDelay={0.1}>
          {platform.audiences.map((audience, i) => {
            const Icon = icons[i] ?? Building2;
            return (
              <article
                key={audience.title}
                className="flex flex-col rounded-2xl bg-marketing-bg p-7 shadow-marketing-card"
              >
                <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-marketing-accent-muted">
                  <Icon className="h-5 w-5 text-marketing-accent" aria-hidden />
                </div>
                <p className="mt-5 text-label-caps text-marketing-accent">{audience.for}</p>
                <h3 className="mt-1 font-display text-section-title text-marketing-foreground">{audience.title}</h3>
                <ul className="mt-4 flex-1 space-y-2.5 border-t border-marketing-border pt-4">
                  {audience.features.map((feature) => (
                    <li key={feature} className="flex gap-2.5 text-sm leading-relaxed text-marketing-muted">
                      <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-marketing-accent" aria-hidden />
                      {feature}
                    </li>
                  ))}
                </ul>
              </article>
            );
          })}
        </Stagger>
      </div>
    </section>
  );
}
