import { type ReactNode } from 'react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { spring } from '../../lib/motion';

/** Interactive card shell for dashboard / list tiles. */
export function AnimatedCard({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  const reduced = useReducedMotion();

  if (reduced) {
    return <div className={className}>{children}</div>;
  }

  return (
    <motion.div
      className={cn(className)}
      whileHover={{ y: -3, boxShadow: '0 8px 24px rgb(0 0 0 / 0.08)' }}
      whileTap={{ scale: 0.995 }}
      transition={spring.soft}
    >
      {children}
    </motion.div>
  );
}
