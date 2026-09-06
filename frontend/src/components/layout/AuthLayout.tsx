import type { ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { Check } from 'lucide-react';
import { cn } from '../../lib/cn';
import { fadeUp, slideInRight, staggerContainer, transition } from '../../lib/motion';

export type AuthPortal = 'platform' | 'company' | 'consultant';

const portalFeatures: Record<AuthPortal, string[]> = {
  platform: [
    'Manage all companies and trials',
    'Review and approve reports',
    'Monitor system health',
  ],
  company: [
    'Track discovery progress',
    'View signals, patterns, and recommendations',
    'Generate governed transformation reports',
  ],
  consultant: [
    'Annotate and review reports',
    'Request employee follow-ups',
    'Collaborate with co-consultants',
  ],
};

type AuthLayoutProps = {
  portal: AuthPortal;
  portalName: string;
  tagline: string;
  children: ReactNode;
};

export function AuthLayout({ portal, portalName, tagline, children }: AuthLayoutProps) {
  const features = portalFeatures[portal];
  const reduced = useReducedMotion();

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <div
        className={cn(
          'relative flex w-full flex-col justify-between overflow-hidden md:w-[40%]',
          'border-r border-border bg-accent-muted px-8 py-10 text-foreground md:px-10 md:py-12'
        )}
      >
        <div
          className="pointer-events-none absolute inset-0 opacity-[0.4] animate-grid-drift bg-[length:64px_64px] bg-[linear-gradient(hsl(var(--border))_1px,transparent_1px),linear-gradient(90deg,hsl(var(--border))_1px,transparent_1px)]"
          aria-hidden
        />
        <div
          className="pointer-events-none absolute right-0 top-0 h-full w-px bg-gradient-to-b from-transparent via-primary to-transparent opacity-40"
          aria-hidden
        />

        <motion.div
          className="relative z-10"
          initial={reduced ? false : 'hidden'}
          animate={reduced ? undefined : 'visible'}
          variants={staggerContainer(0.08)}
        >
          <motion.div variants={fadeUp} transition={transition.reveal} className="flex items-center gap-2">
            <span className="h-6 w-2 shrink-0 rounded-sm bg-primary" aria-hidden />
            <span className="text-3xl font-bold tracking-tight text-foreground">Worktruth</span>
          </motion.div>
          <motion.p
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-8 max-w-sm text-lg font-medium text-foreground"
          >
            {portalName}
          </motion.p>
          <motion.p
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-2 max-w-sm text-sm text-muted-foreground"
          >
            {tagline}
          </motion.p>
          <motion.ul className="mt-8 space-y-3" variants={staggerContainer(0.06)}>
            {features.map((item) => (
              <motion.li
                key={item}
                variants={fadeUp}
                transition={transition.reveal}
                className="flex items-start gap-2 text-sm text-muted-foreground"
              >
                <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                <span>{item}</span>
              </motion.li>
            ))}
          </motion.ul>
        </motion.div>

        <motion.blockquote
          className="relative z-10 mt-10 text-sm italic text-muted-foreground md:mt-0"
          initial={reduced ? false : { opacity: 0 }}
          animate={reduced ? undefined : { opacity: 1 }}
          transition={{ ...transition.reveal, delay: 0.35 }}
        >
          &ldquo;Documents and conversations on one evidence graph — so leadership sees how work actually happens.&rdquo;
        </motion.blockquote>
      </div>

      <div className="flex min-h-screen w-full flex-col items-center justify-center bg-background px-6 py-10 md:w-[60%] md:px-8 md:py-12">
        <motion.div
          className="w-full max-w-md"
          initial={reduced ? false : 'hidden'}
          animate={reduced ? undefined : 'visible'}
          variants={slideInRight}
          transition={transition.reveal}
        >
          {children}
        </motion.div>
      </div>
    </div>
  );
}
