import { marketingContent } from '../content';

export function MarketingFooter() {
  const { footer } = marketingContent;

  return (
    <footer className="border-t border-border bg-surface px-6 py-10 md:px-12">
      <div className="mx-auto max-w-6xl">
        <div className="flex flex-col gap-8 md:flex-row md:items-start md:justify-between">
          <div className="max-w-sm">
            <span className="font-display text-lg font-semibold text-text-primary">Req</span>
            <p className="mt-2 text-sm leading-relaxed text-text-secondary">{footer.tagline}</p>
          </div>
          <nav className="flex flex-wrap gap-x-6 gap-y-2">
            {footer.links.map((link) => (
              <a
                key={link.label}
                href={link.href}
                className="text-sm text-text-secondary hover:text-accent"
              >
                {link.label}
              </a>
            ))}
          </nav>
        </div>
        <p className="mt-8 border-t border-border pt-6 text-center text-sm text-text-secondary md:text-left">
          © {new Date().getFullYear()} Req. All rights reserved.
        </p>
      </div>
    </footer>
  );
}
