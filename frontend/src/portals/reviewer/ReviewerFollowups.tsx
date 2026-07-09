import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type AppNotification, type ReviewerFollowupRow } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, Badge, EmptyState, Button, Skeleton } from '../../components/ui';
import { cn } from '../../lib/cn';

type InboxTab = 'followups' | 'notifications';

export function ReviewerFollowups() {
  const token = useReviewerToken();
  const [tab, setTab] = useState<InboxTab>('followups');
  const [followups, setFollowups] = useState<ReviewerFollowupRow[]>([]);
  const [notifications, setNotifications] = useState<AppNotification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setError('');
    Promise.all([api.reviewerFollowups(token), api.reviewerNotifications(token)])
      .then(([followupData, notificationData]) => {
        setFollowups(followupData.followups);
        setNotifications(notificationData.notifications);
        setUnreadCount(notificationData.unread_count);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load inbox'))
      .finally(() => setLoading(false));
  }, [token]);

  const markAllRead = async () => {
    if (!token) return;
    await api.markAllReviewerNotificationsRead(token);
    setNotifications((items) => items.map((n) => ({ ...n, read_at: n.read_at || new Date().toISOString() })));
    setUnreadCount(0);
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <PageHeader title="Inbox" description="Loading…" />
        <Skeleton variant="card" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Inbox"
        description="Employee follow-ups, co-reviewer mentions, and notifications."
        actions={
          unreadCount > 0 ? (
            <Button variant="secondary" size="sm" onClick={markAllRead}>
              Mark all read ({unreadCount})
            </Button>
          ) : undefined
        }
      />

      <div className="flex gap-2 border-b border-border">
        {(['followups', 'notifications'] as InboxTab[]).map((key) => (
          <button
            key={key}
            type="button"
            onClick={() => setTab(key)}
            className={cn(
              'border-b-2 px-3 py-2 text-sm font-medium capitalize',
              tab === key ? 'border-accent text-accent' : 'border-transparent text-muted-foreground hover:text-foreground'
            )}
          >
            {key}
            {key === 'notifications' && unreadCount > 0 && (
              <span className="ml-2 rounded-full bg-accent px-2 py-0.5 text-xs text-accent-foreground">{unreadCount}</span>
            )}
          </button>
        ))}
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      {tab === 'followups' && (
        <>
          {followups.length === 0 ? (
            <EmptyState title="No follow-ups" description="Follow-up threads appear when you request clarification from an employee." />
          ) : (
            <div className="space-y-3">
              {followups.map((f) => (
                <Card key={f.id}>
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="m-0 text-sm text-muted-foreground">{f.company_name}</p>
                      <h3 className="m-0 font-medium text-foreground">
                        {f.employee_name || `Employee #${f.employee_id}`}
                      </h3>
                      <p className="mt-2 text-sm text-muted-foreground">{f.last_message}</p>
                    </div>
                    <div className="flex flex-col items-end gap-2">
                      <Badge variant={f.status === 'awaiting_reply' ? 'warning' : 'info'}>
                        {f.status.replace(/_/g, ' ')}
                      </Badge>
                      <span className="text-xs text-muted-foreground">{new Date(f.updated_at).toLocaleString()}</span>
                      <Link
                        to={`/reviewer/companies/${f.company_id}/employees/${f.employee_id}/followup`}
                        className="text-sm font-medium text-accent hover:underline"
                      >
                        Open thread →
                      </Link>
                    </div>
                  </div>
                </Card>
              ))}
            </div>
          )}
        </>
      )}

      {tab === 'notifications' && (
        <>
          {notifications.length === 0 ? (
            <EmptyState title="No notifications" description="Co-reviewer messages and discussion mentions will appear here." />
          ) : (
            <div className="space-y-3">
              {notifications.map((n) => (
                <Card key={n.id}>
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p className="m-0 text-sm font-medium text-foreground">{n.title}</p>
                      <p className="mt-1 text-sm text-muted-foreground">{n.body}</p>
                      <p className="mt-2 text-xs text-muted-foreground">{new Date(n.created_at).toLocaleString()}</p>
                    </div>
                    <div className="flex flex-col items-end gap-2">
                      {!n.read_at && <Badge variant="warning">Unread</Badge>}
                      {n.action_url && (
                        <a href={n.action_url} className="text-sm font-medium text-accent hover:underline">
                          Open →
                        </a>
                      )}
                    </div>
                  </div>
                </Card>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
