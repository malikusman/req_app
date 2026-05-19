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
        <Button className="mt-8" onClick={() => setOpen(true)}>
          Request access
        </Button>
      </div>
      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </section>
  );
}
