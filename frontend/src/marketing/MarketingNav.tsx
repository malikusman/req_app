import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Menu, X } from 'lucide-react';
import { Button } from '../components/ui/Button';
import { RequestAccessModal } from './RequestAccessModal';

export function MarketingNav() {
  const [open, setOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-gray-800/50 bg-sidebar/95 backdrop-blur">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
        <Link to="/" className="font-display text-lg font-bold text-text-inverse">
          Req
        </Link>

        <nav className="hidden items-center gap-4 md:flex">
          <Link to="/platform/login" className="text-sm text-gray-300 hover:text-white">
            Sign in
          </Link>
          <Button size="sm" onClick={() => setOpen(true)}>
            Request access
          </Button>
        </nav>

        <button
          type="button"
          className="rounded-md p-2 text-gray-300 hover:text-white md:hidden"
          onClick={() => setMenuOpen((v) => !v)}
          aria-label={menuOpen ? 'Close menu' : 'Open menu'}
        >
          {menuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      {menuOpen && (
        <nav className="border-t border-gray-800/50 px-6 py-4 md:hidden">
          <div className="flex flex-col gap-3">
            <Link
              to="/platform/login"
              className="text-sm text-gray-300 hover:text-white"
              onClick={() => setMenuOpen(false)}
            >
              Sign in
            </Link>
            <Button
              size="sm"
              className="w-full"
              onClick={() => {
                setMenuOpen(false);
                setOpen(true);
              }}
            >
              Request access
            </Button>
          </div>
        </nav>
      )}

      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </header>
  );
}
