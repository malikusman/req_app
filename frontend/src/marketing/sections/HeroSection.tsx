import { useState } from 'react';
import { Button } from '../../components/ui/Button';
import { RequestAccessModal } from '../RequestAccessModal';

export function HeroSection() {
  const [modalOpen, setModalOpen] = useState(false);

  return (
    <section className="relative overflow-hidden border-b border-white/[0.08] bg-sidebar px-6 py-20 text-text-inverse md:px-12 md:py-28">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.09] animate-grid-drift bg-[length:64px_64px] bg-[linear-gradient(rgba(255,255,255,0.07)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.07)_1px,transparent_1px)]"
        aria-hidden
      />
      <div className="relative mx-auto flex max-w-6xl flex-col items-center gap-12 lg:flex-row lg:items-center">
        <div className="flex-1 text-center lg:text-left">
          <p className="text-sm font-medium uppercase tracking-widest text-accent-muted">
            Enterprise workflow discovery
          </p>
          <h1 className="mt-4 font-display text-7xl font-bold leading-none tracking-tight md:text-8xl">
            Req
          </h1>
          <p className="mt-6 max-w-xl text-5xl font-bold leading-tight text-white md:text-6xl">
            Understand how your company actually works.
          </p>
          <p className="mt-4 max-w-lg text-base text-gray-400 md:text-lg">
            Adaptive WhatsApp interviews with your teams — operational intelligence and a transformation
            roadmap in weeks, not quarters.
          </p>
          <div className="mt-8 flex flex-wrap justify-center gap-3 lg:justify-start">
            <Button
              className="px-6 py-3 shadow-button-glow hover:shadow-button-glow"
              onClick={() => setModalOpen(true)}
            >
              Request access
            </Button>
            <Button
              variant="ghost"
              className="border border-gray-600 px-6 py-3 text-text-inverse hover:bg-sidebar-hover"
              onClick={() => document.getElementById('how-it-works')?.scrollIntoView({ behavior: 'smooth' })}
            >
              See how it works
            </Button>
          </div>
        </div>

        <div className="relative w-full flex-1">
          <div
            className="pointer-events-none absolute left-1/2 top-1/2 h-[600px] w-[600px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,rgba(79,70,229,0.15)_0%,transparent_70%)]"
            aria-hidden
          />
          <div className="relative overflow-hidden rounded-lg border border-[#2D2D3A] bg-sidebar-active shadow-hero-mockup">
            <div className="flex items-center gap-3 border-b border-[#2D2D3A] px-4 py-2.5">
              <span className="h-3 w-3 rounded-full bg-red-500/90" />
              <span className="h-3 w-3 rounded-full bg-amber-400/90" />
              <span className="h-3 w-3 rounded-full bg-green-500/90" />
              <div className="ml-2 flex-1 rounded-md bg-black/30 px-3 py-1 text-xs text-gray-400">
                app.reqapp.com
              </div>
            </div>
            <div className="rounded-b bg-surface-muted p-6">
              <p className="text-xs font-semibold uppercase tracking-wide text-text-secondary">
                Discovery intelligence
              </p>
              <p className="mt-2 font-display text-3xl font-bold text-text-primary">72%</p>
              <p className="text-sm text-text-secondary">Report readiness</p>
              <div className="mt-4 grid grid-cols-2 gap-3">
                <div className="rounded-card border border-border bg-surface p-3 shadow-card">
                  <p className="text-2xl font-semibold text-text-primary">24</p>
                  <p className="text-xs text-text-secondary">Interviews completed</p>
                </div>
                <div className="rounded-card border border-border bg-surface p-3 shadow-card">
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
