import { Link, useLocation, useNavigate } from 'react-router-dom';
import { marketingContent } from '../content';

export function MarketingFooter() {
  const { footer } = marketingContent;
  const location = useLocation();
  const navigate = useNavigate();

  const goToSection = (hash: string) => {
    const scroll = () =>
      document.getElementById(hash.slice(1))?.scrollIntoView({ behavior: 'smooth' });
    if (location.pathname === '/') {
      scroll();
    } else {
      navigate('/');
      // Let the homepage mount before scrolling to the section.
      setTimeout(scroll, 250);
    }
  };

  return (
    <footer className="border-t border-marketing-border bg-marketing-surface px-6 py-12 md:px-12">
      <div className="mx-auto max-w-6xl">
        <div className="flex flex-col gap-8 md:flex-row md:items-start md:justify-between">
          <div className="max-w-sm">
            <span className="font-display text-lg font-semibold text-marketing-foreground">Worktruth</span>
            <p className="mt-2 text-sm leading-relaxed text-marketing-muted">{footer.tagline}</p>
          </div>
          <nav className="flex flex-wrap gap-x-8 gap-y-3">
            {footer.links.map((link) =>
              link.href.startsWith('#') ? (
                <button
                  key={link.label}
                  type="button"
                  onClick={() => goToSection(link.href)}
                  className="text-sm text-marketing-muted transition-colors hover:text-marketing-accent"
                >
                  {link.label}
                </button>
              ) : (
                <Link
                  key={link.label}
                  to={link.href}
                  className="text-sm text-marketing-muted transition-colors hover:text-marketing-accent"
                >
                  {link.label}
                </Link>
              )
            )}
          </nav>
        </div>
        <p className="mt-10 border-t border-marketing-border pt-6 text-center text-sm text-marketing-muted md:text-left">
          © {new Date().getFullYear()} Worktruth. All rights reserved.
        </p>
      </div>
    </footer>
  );
}
