import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '../components/ui/Button';
import { RequestAccessModal } from './RequestAccessModal';

export function MarketingNav() {
  const [open, setOpen] = useState(false);
  return (
    <header className="sticky top-0 z-50 border-b border-gray-800/50 bg-sidebar/95 backdrop-blur">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
        <Link to="/" className="font-display text-lg font-bold text-text-inverse">
          Req
        </Link>
        <nav className="flex items-center gap-4">
          <Link to="/platform/login" className="text-sm text-gray-300 hover:text-white">
            Sign in
          </Link>
          <Button size="sm" onClick={() => setOpen(true)}>
            Request access
          </Button>
        </nav>
      </div>
      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </header>
  );
}
