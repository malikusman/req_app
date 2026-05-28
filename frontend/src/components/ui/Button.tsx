import { type ButtonHTMLAttributes, type ReactNode } from 'react';
import { Loader2 } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '../../lib/cn';
import { spring, tapScale } from '../../lib/motion';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';
type Size = 'sm' | 'md' | 'lg';

const variants: Record<Variant, string> = {
  primary:
    'bg-accent text-surface-muted hover:bg-accent-hover hover:shadow-marketing-glow border-transparent',
  secondary: 'bg-surface text-text-primary border-border hover:bg-sidebar-hover/30',
  ghost: 'bg-transparent text-text-secondary border-transparent hover:bg-surface-muted',
  danger: 'bg-status-error text-white border-transparent hover:bg-red-600',
};

const sizes: Record<Size, string> = {
  sm: 'h-8 px-3 text-sm',
  md: 'h-10 px-4 text-sm',
  lg: 'h-11 px-5 text-base',
};

const MotionButton = motion.button;

export function Button({
  variant = 'primary',
  size = 'md',
  loading,
  icon,
  children,
  className,
  disabled,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  size?: Size;
  loading?: boolean;
  icon?: ReactNode;
}) {
  const reduced = useReducedMotion();

  const classes = cn(
    'inline-flex items-center justify-center gap-2 rounded-button border font-medium disabled:opacity-50 disabled:pointer-events-none',
    !reduced && 'transition-none',
    reduced && 'transition-colors',
    variants[variant],
    sizes[size],
    className
  );

  if (reduced) {
    return (
      <button className={classes} disabled={disabled || loading} {...props}>
        {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : icon}
        {children}
      </button>
    );
  }

  return (
    <MotionButton
      className={classes}
      disabled={disabled || loading}
      whileHover={disabled || loading ? undefined : { scale: tapScale.hover }}
      whileTap={disabled || loading ? undefined : { scale: tapScale.tap }}
      transition={spring.snappy}
      {...props}
    >
      {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : icon}
      {children}
    </MotionButton>
  );
}
