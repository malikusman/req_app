import { type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { motion } from 'motion/react';
import { ChevronRight } from 'lucide-react';
import { cn } from '../../lib/cn';
import { fadeUp, transition } from '../../lib/motion';

export type Breadcrumb = { label: string; href?: string };

export function PageHeader({
  title,
  description,
  actions,
  breadcrumbs,
  className,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
  breadcrumbs?: Breadcrumb[];
  className?: string;
}) {
  return (
    <motion.header
      initial="hidden"
      animate="visible"
      variants={fadeUp}
      transition={transition.fast}
      className={cn('mb-8', className)}
    >
      {breadcrumbs && breadcrumbs.length > 0 && (
        <nav aria-label="Breadcrumb" className="mb-3 flex flex-wrap items-center gap-1 text-sm">
          {breadcrumbs.map((crumb, i) => (
            <span key={crumb.label} className="flex items-center gap-1">
              {i > 0 && <ChevronRight className="h-3.5 w-3.5 text-text-secondary" />}
              {crumb.href ? (
                <Link
                  to={crumb.href}
                  className="text-text-secondary transition-colors hover:text-accent"
                >
                  {crumb.label}
                </Link>
              ) : (
                <span className="text-text-secondary">{crumb.label}</span>
              )}
            </span>
          ))}
        </nav>
      )}
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-page-title text-text-primary m-0">{title}</h1>
          {description && (
            <p className="mt-1 text-sm text-text-secondary">{description}</p>
          )}
        </div>
        {actions && <motion.div className="flex shrink-0 items-center gap-2">{actions}</motion.div>}
      </div>
    </motion.header>
  );
}
