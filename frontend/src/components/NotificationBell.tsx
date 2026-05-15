import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type AppNotification } from '../lib/api';
import { useCompanyToken } from '../lib/auth';

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
    <div ref={panelRef} style={{ position: 'relative' }}>
      <button
        type="button"
        className="btn btn-ghost"
        style={{ color: '#fff', borderColor: '#475569', position: 'relative' }}
        onClick={() => setOpen(!open)}
        aria-label="Notifications"
      >
        🔔
        {unreadCount > 0 && (
          <span
            style={{
              position: 'absolute',
              top: 2,
              right: 2,
              background: '#ef4444',
              color: '#fff',
              borderRadius: 999,
              fontSize: '0.65rem',
              minWidth: 16,
              height: 16,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '0 4px',
            }}
          >
            {unreadCount > 9 ? '9+' : unreadCount}
          </span>
        )}
      </button>

      {open && (
        <div
          style={{
            position: 'absolute',
            right: 0,
            top: '100%',
            marginTop: 8,
            width: 360,
            maxHeight: 420,
            overflow: 'auto',
            background: '#fff',
            borderRadius: 8,
            boxShadow: '0 10px 40px rgba(0,0,0,0.15)',
            zIndex: 100,
            color: '#0f172a',
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0.75rem 1rem', borderBottom: '1px solid #e2e8f0' }}>
            <strong>Notifications</strong>
            {unreadCount > 0 && (
              <button type="button" className="btn btn-ghost" style={{ fontSize: '0.8rem', color: '#2563eb' }} onClick={markAll}>
                Mark all read
              </button>
            )}
          </div>
          {notifications.length === 0 && <p style={{ padding: '1rem', color: '#94a3b8', margin: 0 }}>No notifications yet.</p>}
          {notifications.map((n) => (
            <button
              key={n.id}
              type="button"
              onClick={() => openNotification(n)}
              style={{
                display: 'block',
                width: '100%',
                textAlign: 'left',
                padding: '0.75rem 1rem',
                border: 'none',
                borderBottom: '1px solid #f1f5f9',
                background: n.read_at ? '#fff' : '#eff6ff',
                cursor: 'pointer',
              }}
            >
              <strong style={{ display: 'block', fontSize: '0.9rem' }}>{n.title}</strong>
              <small style={{ color: '#64748b' }}>{n.body}</small>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
