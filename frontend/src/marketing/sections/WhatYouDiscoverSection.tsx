import { AlertTriangle, Clock, GitBranch, Hand, Sparkles, Workflow } from 'lucide-react';

const cards = [
  { icon: AlertTriangle, title: 'Bottlenecks', desc: 'Where work stalls across teams and systems.' },
  { icon: Workflow, title: 'Manual workflows', desc: 'Repeated copy-paste and swivel-chair processes.' },
  { icon: Clock, title: 'Time sinks', desc: 'Activities that consume hours without strategic value.' },
  { icon: GitBranch, title: 'Cross-team dependencies', desc: 'Handoffs that break down under load.' },
  { icon: Sparkles, title: 'AI opportunities', desc: 'High-impact automation and augmentation candidates.' },
  { icon: Hand, title: 'Shadow processes', desc: 'Workarounds that never made it into official SOPs.' },
];

export function WhatYouDiscoverSection() {
  return (
    <section className="bg-sidebar px-6 py-20 text-text-inverse md:px-12 md:py-24">
      <div className="mx-auto max-w-6xl">
        <h2 className="font-display text-page-title">What you discover</h2>
        <p className="mt-2 max-w-2xl text-gray-400">
          Operational truth surfaced from real conversations — not assumptions.
        </p>
        <div className="mt-12 grid grid-cols-2 gap-4 lg:grid-cols-3">
          {cards.map((c) => (
            <div
              key={c.title}
              className="rounded-card border border-white/[0.08] bg-white/[0.04] p-5 backdrop-blur-sm transition-all hover:scale-[1.02] hover:bg-white/[0.07]"
            >
              <div className="flex h-9 w-9 items-center justify-center rounded-md bg-accent/10">
                <c.icon className="h-5 w-5 text-accent" />
              </div>
              <h3 className="mt-3 font-semibold">{c.title}</h3>
              <p className="mt-1 text-sm text-gray-400">{c.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
