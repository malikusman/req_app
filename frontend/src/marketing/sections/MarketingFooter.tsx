import { Link, useLocation, useNavigate } from 'react-router-dom';
import { MjadiLogo } from '../../components/brand/MjadiLogo';
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
    <footer className="border-t border-marketing-border bg-marketing-surface px-5 py-12 sm:px-8">
      <div className="mx-auto max-w-5xl">
        <div className="flex flex-col gap-8 md:flex-row md:items-start md:justify-between">
          <div className="max-w-sm">
            <MjadiLogo wordmarkClassName="text-lg font-bold" />
            <p className="m-0 mt-3 text-sm leading-relaxed text-marketing-muted">{footer.tagline}</p>
          </div>
          <nav className="grid gap-x-10 gap-y-3 sm:grid-cols-2">
            {footer.links.map((link) =>
              link.href.startsWith('#') ? (
                <button
                  key={link.label}
                  type="button"
                  onClick={() => goToSection(link.href)}
                  className="text-left text-sm text-marketing-muted transition-colors hover:text-marketing-accent"
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

        {/*
          This sat under the hero in eleven-pixel type, arguing with the first
          thing a visitor read. It belongs here — still said plainly, no longer
          competing with the headline.
        */}
        <div className="mt-10 border-t border-marketing-border pt-6">
          <p className="m-0 max-w-2xl text-xs leading-relaxed text-marketing-muted">
            {footer.disclaimer}
          </p>
          <p className="m-0 mt-4 text-xs text-marketing-muted">
            © {new Date().getFullYear()} Mjadi. All rights reserved.
          </p>
        </div>
      </div>
    </footer>
  );
}
