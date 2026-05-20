import { useState } from 'react';
import { Button } from '../../components/ui/Button';
import { RequestAccessModal } from '../RequestAccessModal';

export function FinalCtaSection() {
  const [open, setOpen] = useState(false);
  return (
    <section className="bg-sidebar px-6 py-20 text-center text-text-inverse md:px-12">
      <div className="mx-auto max-w-2xl">
        <h2 className="font-display text-3xl font-bold">Ready to see inside your organization?</h2>
        <p className="mt-3 text-gray-400">Request a guided walkthrough with our team.</p>
        <div className="relative mt-8 inline-flex items-center justify-center">
          <span
            className="pointer-events-none absolute inset-0 rounded-button border border-accent/20 animate-cta-pulse"
            aria-hidden
          />
          <span
            className="pointer-events-none absolute inset-0 rounded-button border border-accent/20 animate-cta-pulse-delayed"
            aria-hidden
          />
          <Button className="relative text-lg px-8 py-4 shadow-button-glow" onClick={() => setOpen(true)}>
            Request access
          </Button>
        </div>
      </div>
      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </section>
  );
}
