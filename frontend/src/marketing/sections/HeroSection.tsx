import { useState } from 'react';
import { Button } from '../../components/ui/Button';
import { RequestAccessModal } from '../RequestAccessModal';

export function HeroSection() {
  const [modalOpen, setModalOpen] = useState(false);

  return (
    <section className="relative overflow-hidden bg-sidebar px-6 py-24 text-text-inverse md:px-12">
      <div className="pointer-events-none absolute inset-0 opacity-[0.04] animate-grid-drift bg-[length:64px_64px] bg-[linear-gradient(#fff_1px,transparent_1px),linear-gradient(90deg,#fff_1px,transparent_1px)]" />
      <div className="relative mx-auto flex max-w-6xl flex-col gap-12 lg:flex-row lg:items-center">
        <div className="flex-1">
          <p className="text-sm font-medium uppercase tracking-widest text-accent-muted">Enterprise workflow discovery</p>
          <h1 className="mt-4 font-display text-4xl font-bold leading-tight md:text-5xl">
            Req
          </h1>
          <p className="mt-4 max-w-xl text-lg text-gray-300">
            Understand how your company actually works. Then fix it with AI.
          </p>
          <p className="mt-2 max-w-lg text-sm text-gray-400">
            Adaptive WhatsApp interviews with your teams — operational intelligence and a transformation roadmap in weeks, not quarters.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Button onClick={() => setModalOpen(true)}>Request access</Button>
            <Button variant="ghost" className="border border-gray-600 text-text-inverse hover:bg-sidebar-hover" onClick={() => document.getElementById('how-it-works')?.scrollIntoView({ behavior: 'smooth' })}>
              See how it works
            </Button>
          </div>
        </div>
        <div className="flex-1">
          <div className="rounded-lg border border-gray-700 bg-sidebar-active p-2 shadow-modal">
            <div className="flex gap-1.5 border-b border-gray-700 px-3 py-2">
              <span className="h-2.5 w-2.5 rounded-full bg-red-500/80" />
              <span className="h-2.5 w-2.5 rounded-full bg-amber-500/80" />
              <span className="h-2.5 w-2.5 rounded-full bg-green-500/80" />
            </div>
            <div className="rounded bg-surface-muted p-6">
              <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">Discovery intelligence</p>
              <p className="mt-2 font-display text-3xl font-bold text-text-primary">72%</p>
              <p className="text-sm text-text-secondary">Report readiness</p>
              <div className="mt-4 grid grid-cols-2 gap-3">
                <div className="rounded-card border border-border bg-surface p-3">
                  <p className="text-2xl font-semibold text-text-primary">24</p>
                  <p className="text-xs text-text-secondary">Interviews completed</p>
                </div>
                <div className="rounded-card border border-border bg-surface p-3">
                  <p className="text-2xl font-semibold text-text-primary">8</p>
                  <p className="text-xs text-text-secondary">Patterns detected</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <RequestAccessModal open={modalOpen} onClose={() => setModalOpen(false)} />
    </section>
  );
}
