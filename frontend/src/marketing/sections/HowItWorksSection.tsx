import { ScrollReveal, Stagger } from '../../components/motion';
import { Section, SectionHeader } from '../components/Section';
import { marketingContent } from '../content';

/**
 * The three stages, plus the three facts that used to be a twelve-bullet
 * "platform" section of its own.
 *
 * That section described our machinery in our words — three audience columns,
 * four bullets each. An owner needs three things from it: what this asks of
 * their staff, what protects those staff, and who checks the work. Those sit
 * here, where the commitment is being described anyway.
 */
export function HowItWorksSection() {
  const { howItWorks } = marketingContent;

  return (
    <Section id="how-it-works" tone="surface" width="wide">
      <SectionHeader eyebrow={howItWorks.eyebrow} title={howItWorks.title} lede={howItWorks.subtitle} />

      <Stagger className="mt-12 grid gap-8 md:grid-cols-3 lg:mt-14" staggerDelay={0.09}>
        {howItWorks.steps.map((step, i) => (
          <article key={step.title} className="border-t-2 border-marketing-accent pt-6">
            <p className="m-0 font-display text-sm font-bold tabular-nums text-marketing-accent">
              {String(i + 1).padStart(2, '0')}
            </p>
            <h3 className="m-0 mt-2 font-display text-xl font-semibold text-marketing-foreground">
              {step.title}
            </h3>
            <p className="m-0 mt-3 text-pretty text-[0.9375rem] leading-relaxed text-marketing-muted">
              {step.description}
            </p>
            <ul className="m-0 mt-4 list-none space-y-2 p-0">
              {step.details.map((detail) => (
                <li key={detail} className="flex gap-2.5 text-sm leading-relaxed text-marketing-muted">
                  <span className="mt-[0.5em] h-1 w-1 shrink-0 rounded-full bg-marketing-accent" aria-hidden />
                  {detail}
                </li>
              ))}
            </ul>
          </article>
        ))}
      </Stagger>

      {/* Written into the content from the start, never rendered until now. */}
      <ScrollReveal>
        <p className="m-0 mt-12 text-pretty font-display text-lg font-medium text-marketing-foreground sm:text-xl">
          {howItWorks.closing}
        </p>
      </ScrollReveal>

      <ScrollReveal>
        <dl className="m-0 mt-10 grid gap-x-8 gap-y-6 border-t border-marketing-border pt-8 sm:grid-cols-3">
          {howItWorks.facts.map((fact) => (
            <div key={fact.label}>
              <dt className="text-label-caps text-marketing-accent">{fact.label}</dt>
              <dd className="m-0 mt-1.5 text-pretty text-sm leading-relaxed text-marketing-muted">
                {fact.body}
              </dd>
            </div>
          ))}
        </dl>
      </ScrollReveal>
    </Section>
  );
}
