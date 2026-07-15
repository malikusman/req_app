import { useEffect, useRef, useState } from 'react';
import { Bell } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { api, type AppNotification } from '../lib/api';
import { useCompanyToken } from '../lib/auth';
import { Button } from './ui';
import { cn } from '../lib/cn';

export function NotificationBell() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  const [notifications, setNotifications] = useState<AppNotification[]>([]);
  const panelRef = useRef<HTMLDivElement>(null);

  const load = () => {
    if (!token) return;
    api.companyNotifications(token, 1).then((data) => {
      setNotifications(data.notifications);
      setUnreadCount(data.unread_count);
    });
  };

  useEffect(() => {
    load();
    const interval = setInterval(load, 30000);
    return () => clearInterval(interval);
  }, [token]);

  useEffect(() => {
    if (!token || !open) return;
    load();
  }, [open, token]);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    if (open) document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, [open]);

  const markRead = async (n: AppNotification) => {
    if (!token || n.read_at) return;
    await api.markNotificationRead(token, n.id);
    load();
  };

  const markAll = async () => {
    if (!token) return;
    await api.markAllNotificationsRead(token);
    load();
  };

  const openNotification = (n: AppNotification) => {
    markRead(n);
    setOpen(false);
    if (n.action_url) {
      try {
        const path = new URL(n.action_url).pathname;
        navigate(path);
      } catch {
        window.location.href = n.action_url;
      }
    }
  };

  return (
    <div ref={panelRef} className="relative">
      <Button
        type="button"
        variant="ghost"
        size="sm"
        className="relative text-foreground hover:bg-muted"
        onClick={() => setOpen(!open)}
        aria-label="Notifications"
        icon={<Bell className="h-4 w-4" />}
      >
        <span className="sr-only">Notifications</span>
        {unreadCount > 0 && (
          <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-status-error px-1 text-[10px] font-medium text-white">
            {unreadCount > 9 ? '9+' : unreadCount}
          </span>
        )}
      </Button>

      {open && (
        <div className="absolute right-0 top-full z-50 mt-2 w-[min(360px,calc(100vw-1.5rem))] max-h-[min(420px,70dvh)] overflow-hidden rounded-card border border-border bg-surface shadow-card">
          <div className="flex items-center justify-between border-b border-border px-4 py-3">
            <strong className="text-sm text-text-primary">Notifications</strong>
            {unreadCount > 0 && (
              <button
                type="button"
                className="text-xs font-medium text-accent hover:underline"
                onClick={markAll}
              >
                Mark all read
              </button>
            )}
          </div>
          <div className="max-h-[360px] overflow-y-auto">
            {notifications.length === 0 && (
              <p className="p-4 text-sm text-text-secondary">No notifications yet.</p>
            )}
            {notifications.map((n) => (
              <button
                key={n.id}
                type="button"
                onClick={() => openNotification(n)}
                className={cn(
                  'block w-full border-b border-border px-4 py-3 text-left transition-colors last:border-0',
                  n.read_at ? 'bg-surface hover:bg-surface-muted' : 'bg-accent-muted/30 hover:bg-accent-muted/50'
                )}
              >
                <strong className="block text-sm text-text-primary">{n.title}</strong>
                <span className="text-xs text-text-secondary">{n.body}</span>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
