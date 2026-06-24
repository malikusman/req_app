import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  type ReactNode,
} from 'react';
import { toast as sonnerToast } from 'sonner';
import type { ToastVariant } from './Toast';

type ToastInput = {
  title: string;
  description?: string;
  variant?: ToastVariant;
  duration?: number;
};

type ToastContextValue = {
  toast: (input: ToastInput) => string;
  dismiss: (id: string | number) => void;
};

const ToastContext = createContext<ToastContextValue | null>(null);

let toastId = 0;

export function ToastProvider({ children }: { children: ReactNode }) {
  const dismiss = useCallback((id: string | number) => {
    sonnerToast.dismiss(id);
  }, []);

  const toast = useCallback((input: ToastInput) => {
    const id = `toast-${++toastId}`;
    const duration = input.duration ?? 5000;
    const options = {
      id,
      description: input.description,
      duration: duration > 0 ? duration : Infinity,
    };

    switch (input.variant) {
      case 'success':
        sonnerToast.success(input.title, options);
        break;
      case 'error':
        sonnerToast.error(input.title, options);
        break;
      case 'warning':
        sonnerToast.warning(input.title, options);
        break;
      default:
        sonnerToast(input.title, options);
    }

    return id;
  }, []);

  const value = useMemo(() => ({ toast, dismiss }), [toast, dismiss]);

  return <ToastContext.Provider value={value}>{children}</ToastContext.Provider>;
}

export function useToast() {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    throw new Error('useToast must be used within ToastProvider');
  }
  return ctx;
}
