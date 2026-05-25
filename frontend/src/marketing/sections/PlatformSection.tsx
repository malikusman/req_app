import { Building2, ClipboardCheck, Settings2 } from 'lucide-react';
import { ScrollReveal, Stagger } from '../../components/motion';
import { marketingContent } from '../content';

const icons = [Building2, ClipboardCheck, Settings2] as const;

export function PlatformSection() {
  const { platform } = marketingContent;

  return (
    <section id="platform" className="bg-surface-muted px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <ScrollReveal>
          <h2 className="font-display text-page-title text-text-primary">{platform.title}</h2>
          <p className="mt-3 max-w-3xl text-lg text-text-secondary">{platform.subtitle}</p>
        </ScrollReveal>
        <Stagger className="mt-14 grid gap-8 lg:grid-cols-3" staggerDelay={0.1}>
          {platform.audiences.map((audience, i) => {
            const Icon = icons[i] ?? Building2;
            return (
              <article
                key={audience.title}
                className="flex flex-col rounded-card border border-border bg-surface p-6 shadow-card"
              >
                <div className="flex h-10 w-10 items-center justify-center rounded-button bg-accent-muted">
                  <Icon className="h-5 w-5 text-accent" aria-hidden />
                </div>
                <p className="mt-4 text-label-caps text-accent">{audience.for}</p>
                <h3 className="mt-1 font-display text-section-title text-text-primary">{audience.title}</h3>
                <ul className="mt-4 flex-1 space-y-2.5 border-t border-border pt-4">
                  {audience.features.map((feature) => (
                    <li key={feature} className="flex gap-2 text-sm leading-relaxed text-text-secondary">
                      <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-accent" aria-hidden />
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
