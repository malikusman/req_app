import { useState } from 'react';
import { Link } from 'react-router-dom';
import { motion, AnimatePresence, useReducedMotion } from 'motion/react';
import { Menu, X } from 'lucide-react';
import { Button } from '@/components/shadcn/button';
import { fadeUp, transition } from '../lib/motion';
import { marketingContent } from './content';
import { RequestAccessModal } from './RequestAccessModal';

export function MarketingNav() {
  const [open, setOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const reduced = useReducedMotion();
  const { nav } = marketingContent;

  const scrollTo = (href: string) => {
    if (!href.startsWith('#')) return;
    document.querySelector(href)?.scrollIntoView({ behavior: 'smooth' });
    setMenuOpen(false);
  };

  return (
    <motion.header
      className="sticky top-0 z-50 border-b border-marketing-border bg-marketing-bg/80 backdrop-blur-md"
      initial={reduced ? false : { y: -16, opacity: 0 }}
      animate={reduced ? undefined : { y: 0, opacity: 1 }}
      transition={transition.normal}
    >
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
        <Link to="/" className="font-display text-lg font-bold text-marketing-foreground">
          Worktruth
        </Link>

        <nav className="hidden items-center gap-6 md:flex">
          {nav.links.map((link) => (
            <button
              key={link.href}
              type="button"
              onClick={() => scrollTo(link.href)}
              className="text-sm text-marketing-muted transition-colors hover:text-marketing-accent"
            >
              {link.label}
            </button>
          ))}
          <Link
            to="/platform/login"
            className="text-sm text-marketing-muted transition-colors hover:text-marketing-foreground"
          >
            {nav.signInLabel}
          </Link>
          <Button size="sm" onClick={() => setOpen(true)}>
            {nav.ctaLabel}
          </Button>
        </nav>

        <button
          type="button"
          className="rounded-md p-2 text-marketing-muted hover:text-marketing-foreground md:hidden"
          onClick={() => setMenuOpen((v) => !v)}
          aria-label={menuOpen ? 'Close menu' : 'Open menu'}
        >
          {menuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
        </button>
      </div>

      <AnimatePresence>
        {menuOpen && (
          <motion.nav
            className="border-t border-marketing-border px-6 py-4 md:hidden"
            initial="hidden"
            animate="visible"
            exit="hidden"
            variants={{
              hidden: { height: 0, opacity: 0 },
              visible: { height: 'auto', opacity: 1 },
            }}
            transition={transition.fast}
          >
            <motion.div className="flex flex-col gap-3" variants={fadeUp}>
              {nav.links.map((link) => (
                <button
                  key={link.href}
                  type="button"
                  className="text-left text-sm text-marketing-muted hover:text-marketing-accent"
                  onClick={() => scrollTo(link.href)}
                >
                  {link.label}
                </button>
              ))}
              <Link
                to="/platform/login"
                className="text-sm text-marketing-muted"
                onClick={() => setMenuOpen(false)}
              >
                {nav.signInLabel}
              </Link>
              <Button
                size="sm"
                className="w-full"
                onClick={() => {
                  setMenuOpen(false);
                  setOpen(true);
                }}
              >
                {nav.ctaLabel}
              </Button>
            </motion.div>
          </motion.nav>
        )}
      </AnimatePresence>

      <RequestAccessModal open={open} onClose={() => setOpen(false)} />
    </motion.header>
  );
}
