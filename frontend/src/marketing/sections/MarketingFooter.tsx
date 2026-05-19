import { Link } from 'react-router-dom';

export function MarketingFooter() {
  return (
    <footer className="border-t border-border bg-surface px-6 py-8 md:px-12">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 sm:flex-row">
        <span className="font-display font-semibold text-text-primary">Req</span>
        <p className="text-sm text-text-secondary">© {new Date().getFullYear()} Req. All rights reserved.</p>
        <Link to="#" className="text-sm text-text-secondary hover:text-accent">
          Privacy
        </Link>
      </div>
    </footer>
  );
}
