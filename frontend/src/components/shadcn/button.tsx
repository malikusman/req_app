import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-marketing-accent focus-visible:ring-offset-2 focus-visible:ring-offset-marketing-bg disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        default:
          'bg-marketing-accent text-marketing-bg hover:bg-marketing-accent-hover shadow-marketing-glow',
        destructive: 'bg-status-error text-white hover:bg-red-600',
        outline:
          'border border-marketing-border bg-transparent text-marketing-foreground hover:bg-white/5',
        secondary:
          'bg-white/10 text-marketing-foreground backdrop-blur-sm border border-white/20 hover:bg-white/20',
        ghost: 'text-marketing-muted hover:bg-white/5 hover:text-marketing-foreground',
        link: 'text-marketing-accent underline-offset-4 hover:underline',
        glass:
          'bg-white/10 text-marketing-foreground backdrop-blur-md border border-white/20 hover:bg-white/20',
      },
      size: {
        default: 'h-10 px-4 py-2',
        sm: 'h-9 rounded-md px-3',
        lg: 'h-11 rounded-md px-8 text-base',
        icon: 'h-10 w-10',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'default',
    },
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, ...props }, ref) => (
    <button className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />
  )
);
Button.displayName = 'Button';

export { Button, buttonVariants };
