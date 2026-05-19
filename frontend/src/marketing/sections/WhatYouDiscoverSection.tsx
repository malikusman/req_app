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
    <section className="bg-sidebar px-6 py-20 text-text-inverse md:px-12">
      <div className="mx-auto max-w-6xl">
        <h2 className="font-display text-page-title">What you discover</h2>
        <p className="mt-2 max-w-2xl text-gray-400">Operational truth surfaced from real conversations — not assumptions.</p>
        <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {cards.map((c) => (
            <div key={c.title} className="rounded-card border border-gray-700/80 bg-sidebar-active/50 p-5 backdrop-blur-sm">
              <c.icon className="h-5 w-5 text-accent-muted" />
              <h3 className="mt-3 font-semibold">{c.title}</h3>
              <p className="mt-1 text-sm text-gray-400">{c.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
