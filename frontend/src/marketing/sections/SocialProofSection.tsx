import { ScrollReveal, Stagger, LogoMarquee } from '../../components/motion';
import { marketingContent } from '../content';

export function SocialProofSection() {
  const { socialProof } = marketingContent;

  return (
    <section className="bg-marketing-bg px-6 py-20 md:px-12 md:py-24">
      <div className="mx-auto max-w-6xl text-center">
        <ScrollReveal>
          <p className="text-label-caps text-marketing-gold">{socialProof.eyebrow}</p>
        </ScrollReveal>
        <div className="mt-8 [&_span]:text-marketing-muted">
          <LogoMarquee items={[...socialProof.logos]} />
        </div>
        <ScrollReveal variant="fadeIn" delay={0.1}>
          <blockquote className="mx-auto mt-16 max-w-3xl rounded-card border border-marketing-border bg-marketing-surface/50 p-8 backdrop-blur-sm">
            <p className="font-display text-2xl italic leading-relaxed text-marketing-foreground md:text-3xl">
              &ldquo;{socialProof.quote.text}&rdquo;
            </p>
            <footer className="mt-4 text-sm text-marketing-muted">
              — {socialProof.quote.attribution}, {socialProof.quote.company}
            </footer>
          </blockquote>
        </ScrollReveal>
        <Stagger className="mt-16 grid grid-cols-1 gap-8 sm:grid-cols-3" staggerDelay={0.1}>
          {socialProof.stats.map((stat) => (
            <div key={stat.label} className="border-t border-marketing-border pt-8">
              <div className="mx-auto mb-4 h-0 w-12 border-t-2 border-marketing-accent" aria-hidden />
              <p className="font-display text-5xl font-bold text-marketing-accent md:text-6xl">{stat.value}</p>
              <p className="mt-2 text-sm text-marketing-muted">{stat.label}</p>
            </div>
          ))}
        </Stagger>
        <p className="mx-auto mt-10 max-w-2xl text-xs text-marketing-muted">{socialProof.disclaimer}</p>
      </div>
    </section>
  );
}
