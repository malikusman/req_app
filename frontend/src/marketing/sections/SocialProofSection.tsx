import { MessageCircle } from 'lucide-react';
import { ScrollReveal } from '../../components/motion';
import { marketingContent } from '../content';

export function SocialProofSection() {
  const { method } = marketingContent;

  return (
    <section className="border-y border-marketing-border bg-marketing-surface px-6 py-20 md:px-12 md:py-24">
      <div className="mx-auto max-w-4xl">
        <ScrollReveal variant="fadeIn">
          <figure className="relative m-0 rounded-3xl bg-marketing-accent-muted p-8 md:p-12">
            <span
              className="absolute -top-5 left-8 flex h-10 w-10 items-center justify-center rounded-full bg-marketing-accent text-white shadow-card"
              aria-hidden
            >
              <MessageCircle className="h-5 w-5" />
            </span>
            <p className="m-0 text-label-caps text-marketing-accent">{method.eyebrow}</p>
            <blockquote className="m-0 mt-4">
              <p className="m-0 font-display text-2xl font-semibold leading-relaxed text-marketing-foreground md:text-3xl">
                &ldquo;{method.quote}&rdquo;
              </p>
            </blockquote>
            <figcaption className="mt-6 text-sm text-marketing-muted">{method.label}</figcaption>
          </figure>
        </ScrollReveal>
      </div>
    </section>
  );
}
