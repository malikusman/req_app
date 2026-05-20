import { MessageCircle, Brain, FileText } from 'lucide-react';

const steps = [
  {
    icon: MessageCircle,
    title: 'Employees chat on WhatsApp',
    description: 'Adaptive interviews meet people where they work. No surveys, no portals — just a natural conversation.',
  },
  {
    icon: Brain,
    title: 'AI extracts workflow intelligence',
    description: 'Pain points, tools, bottlenecks, and cross-team dependencies are structured into signals and patterns.',
  },
  {
    icon: FileText,
    title: 'You get a transformation roadmap',
    description: 'A professional report with prioritized AI recommendations your leadership can act on immediately.',
  },
];

export function HowItWorksSection() {
  return (
    <section id="how-it-works" className="bg-surface-muted px-6 py-24 md:px-12 md:py-28">
      <div className="mx-auto max-w-6xl">
        <h2 className="font-display text-page-title text-text-primary">How it works</h2>
        <p className="mt-2 max-w-2xl text-text-secondary">
          Three steps from frontline insight to executive-ready recommendations.
        </p>
        <div className="mt-14 grid gap-8 md:grid-cols-1 lg:grid-cols-3">
          {steps.map((step, i) => (
            <div
              key={step.title}
              className="rounded-card border border-border border-l-2 border-l-accent bg-surface p-6 shadow-card transition-all hover:-translate-y-0.5 hover:shadow-md"
            >
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-accent-muted text-sm font-bold text-accent">
                {i + 1}
              </span>
              <step.icon className="mt-4 h-6 w-6 text-accent" />
              <h3 className="mt-3 font-display text-section-title text-text-primary">{step.title}</h3>
              <p className="mt-2 text-sm text-text-secondary">{step.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
