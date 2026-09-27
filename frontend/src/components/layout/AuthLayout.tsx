import type { ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { Check } from 'lucide-react';
import { cn } from '../../lib/cn';
import { fadeUp, slideInRight, staggerContainer, transition } from '../../lib/motion';
import { MjadiMark } from '../brand/MjadiLogo';

export type AuthPortal = 'platform' | 'company' | 'consultant';

// In the site's own voice: what each person does here, in their words.
const portalFeatures: Record<AuthPortal, string[]> = {
  platform: [
    'Companies, trials and reports in one place',
    'Approve a report once it passes its checks',
    'See how every company’s interviews are going',
  ],
  company: [
    'See who has taken part, department by department',
    'Read where your team’s time goes, role by role',
    'Talk to the consultant reviewing your findings',
  ],
  consultant: [
    'Review each company’s findings before the client sees them',
    'Correct, merge and approve what the interviews found',
    'Ask an employee a follow-up when something is unclear',
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
          'border-b border-border bg-accent-muted px-5 py-4 text-foreground md:border-b-0 md:border-r md:px-10 md:py-12'
        )}
      >
        <div
          className="pointer-events-none absolute inset-0 hidden opacity-[0.4] bg-[length:64px_64px] md:block bg-[linear-gradient(hsl(var(--border))_1px,transparent_1px),linear-gradient(90deg,hsl(var(--border))_1px,transparent_1px)]"
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
            <MjadiMark className="h-7 w-7 md:h-9 md:w-9" />
            <span className="text-xl font-bold tracking-tight text-foreground md:text-3xl">Mjadi</span>
            {/* On a phone the portal name rides in the header; the rest waits for room. */}
            <span className="ml-1 text-sm text-muted-foreground md:hidden">· {portalName.replace(/^Mjadi\s*—\s*/, "")}</span>
          </motion.div>
          <motion.p
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-8 hidden max-w-sm text-lg font-medium text-foreground md:block"
          >
            {portalName}
          </motion.p>
          <motion.p
            variants={fadeUp}
            transition={transition.reveal}
            className="mt-2 hidden max-w-sm text-sm text-muted-foreground md:block"
          >
            {tagline}
          </motion.p>
          <motion.ul className="mt-8 hidden space-y-3 md:block" variants={staggerContainer(0.06)}>
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

      </div>

      <div className="flex w-full flex-1 flex-col items-center justify-start bg-background px-5 py-8 md:min-h-screen md:w-[60%] md:justify-center md:px-8 md:py-12">
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
