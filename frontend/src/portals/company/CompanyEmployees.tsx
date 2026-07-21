import { useEffect, useState, useMemo } from 'react';
import { api, type Employee } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import {
  PageHeader,
  Card,
  Input,
  Button,
  DataTable,
  Badge,
  FunnelChart,
  EmptyState,
  Modal,
} from '../../components/ui';
import { EmployeeDigestModal } from './EmployeeDigestModal';

function participationBadge(status: string) {
  if (status === 'completed') return 'success' as const;
  if (status === 'started') return 'info' as const;
  if (status === 'invited') return 'warning' as const;
  return 'neutral' as const;
}

function nudgeStatusLabel(employee: Employee): string | null {
  const nudge = employee.latest_nudge;
  if (!nudge) return null;

  if (nudge.delivery_status === 'queued') return 'Queued';
  if (nudge.delivery_status === 'sent') {
    if (nudge.channel === 'whatsapp_and_email') return 'Sent (WhatsApp + email)';
    return 'Sent (WhatsApp)';
  }
  if (nudge.delivery_status === 'partial') return 'Partially sent';
  if (nudge.delivery_status === 'failed') return 'Failed';
  return nudge.delivery_status;
}

export function CompanyEmployees() {
  const token = useCompanyToken();
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [department, setDepartment] = useState('');
  const [preferredChannel, setPreferredChannel] = useState<'whatsapp' | 'web' | 'both'>('whatsapp');
  const [newCode, setNewCode] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [nudgeMsg, setNudgeMsg] = useState('');
  const [loading, setLoading] = useState(true);
  const [inviting, setInviting] = useState(false);
  const [nudgingId, setNudgingId] = useState<number | null>(null);
  const [nudgeConfirmEmployee, setNudgeConfirmEmployee] = useState<Employee | null>(null);
  const [editingPhoneId, setEditingPhoneId] = useState<number | null>(null);
  const [editPhone, setEditPhone] = useState('');
  const [savingPhone, setSavingPhone] = useState(false);
  const [digestEmployee, setDigestEmployee] = useState<Employee | null>(null);
  const [usage, setUsage] = useState<{
    conversations_used: number;
    conversation_limit: number | null;
    remaining: number | null;
    limit_reached: boolean;
  } | null>(null);

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .companyEmployees(token)
      .then((d) => setEmployees(d.employees))
      .catch(() => setLoadError('Could not load employees.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  useEffect(() => {
    if (!token) return;
    api.companyDashboard(token).then((d) => setUsage(d.usage)).catch(() => undefined);
  }, [token]);

  const funnelStages = useMemo(() => {
    const invited = employees.length;
    const started = employees.filter((e) => e.participation_status === 'started' || e.participation_status === 'completed').length;
    const completed = employees.filter((e) => e.participation_status === 'completed').length;
    return [
      { label: 'Invited', count: invited },
      { label: 'Started', count: started },
      { label: 'Completed', count: completed },
    ];
  }, [employees]);

  const invite = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    setNewCode(null);
    setInviting(true);
    try {
      const res = await api.inviteEmployee(
        token,
        phone,
        displayName || undefined,
        department || undefined,
        email || undefined,
        email ? preferredChannel : undefined
      );
      setNewCode(res.access_code);
      setPhone('');
      setEmail('');
      setDisplayName('');
      setDepartment('');
      setPreferredChannel('whatsapp');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Invite failed');
    } finally {
      setInviting(false);
    }
  };

  const sendNudge = async (employeeId: number) => {
    if (!token) return;
    setNudgeMsg('');
    setError('');
    setNudgingId(employeeId);
    try {
      const res = await api.nudgeEmployee(token, employeeId);
      setNudgeMsg(res.message || 'Nudge queued.');
      setNudgeConfirmEmployee(null);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Nudge failed');
    } finally {
      setNudgingId(null);
    }
  };

  const nudgeChannelsLabel = (employee: Employee) => {
    if (employee.email) return 'WhatsApp and email';
    return 'WhatsApp';
  };

  const copyCode = (code: string) => {
    navigator.clipboard.writeText(code);
  };

  const startPhoneEdit = (employee: Employee) => {
    setEditingPhoneId(employee.id);
    setEditPhone(employee.phone_e164);
    setError('');
  };

  const savePhone = async (employeeId: number) => {
    if (!token || !editPhone.trim()) return;
    setSavingPhone(true);
    setError('');
    try {
      await api.updateEmployeePhone(token, employeeId, editPhone.trim());
      setEditingPhoneId(null);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update phone');
    } finally {
      setSavingPhone(false);
    }
  };

  return (
    <div className="space-y-8">
      <PageHeader
        title="Employees"
        description="Invite employees, nudge stalled interviews, and manage private value digests."
      />

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <Card title="Invite employee">
        {usage && usage.conversation_limit != null && (
          <p className="mb-3 text-sm text-text-secondary">
            Discovery conversations: {usage.conversations_used} / {usage.conversation_limit} used
            {usage.remaining != null ? ` (${usage.remaining} remaining)` : ''}.
            {usage.limit_reached
              ? ' Limit reached — upgrade billing before new interviews can start.'
              : ' Invites succeed now; the limit applies when an employee starts discovery (WhatsApp or web).'}
          </p>
        )}
        {error && <p className="text-sm text-status-error">{error}</p>}
        {nudgeMsg && (
          <p className="mb-4 rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">{nudgeMsg}</p>
        )}
        {newCode && (
          <div className="mb-4 rounded-button border border-border bg-surface-muted p-4">
            <p className="m-0 text-sm text-text-secondary">Access code (copy and share privately):</p>
            <p className="mt-2 font-mono text-lg font-semibold text-text-primary">{newCode}</p>
            <Button variant="secondary" size="sm" className="mt-2" onClick={() => copyCode(newCode)}>
              Copy code
            </Button>
          </div>
        )}
        <form onSubmit={invite} className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          <Input
            label="Phone E.164"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            required
            placeholder="+14155551234"
          />
          <Input
            label="Email (optional)"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="employee@company.com"
          />
          <Input label="Name" value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
          <Input label="Department" value={department} onChange={(e) => setDepartment(e.target.value)} />
          {email && (
            <label className="flex flex-col gap-1 text-sm">
              <span className="text-text-secondary">Invite channel</span>
              <select
                className="rounded-button border border-border bg-surface px-3 py-2 text-text-primary"
                value={preferredChannel}
                onChange={(e) => setPreferredChannel(e.target.value as 'whatsapp' | 'web' | 'both')}
              >
                <option value="whatsapp">WhatsApp only</option>
                <option value="web">Browser only</option>
                <option value="both">WhatsApp + browser</option>
              </select>
            </label>
          )}
          <div className="md:col-span-2 lg:col-span-4">
            <Button type="submit" loading={inviting}>
              {email && preferredChannel === 'web' ? 'Send email invite' : 'Send invite'}
            </Button>
          </div>
        </form>
      </Card>

      <Card title="Participation funnel">
        <FunnelChart stages={funnelStages} />
      </Card>

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'employee',
            header: 'Employee',
            render: (e) => (
              <div>
                <span className="font-medium">{e.display_name || '—'}</span>
                {e.stalled && (
                  <Badge variant="warning" className="ml-2">
                    stalled
                  </Badge>
                )}
                {editingPhoneId === e.id ? (
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <Input
                      value={editPhone}
                      onChange={(ev) => setEditPhone(ev.target.value)}
                      placeholder="+14155551234"
                      className="max-w-[180px]"
                    />
                    <Button size="sm" loading={savingPhone} onClick={() => savePhone(e.id)}>
                      Save
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => setEditingPhoneId(null)}>
                      Cancel
                    </Button>
                  </div>
                ) : (
                  <p className="m-0 text-xs text-text-secondary">
                    {e.phone_e164}
                    {e.email ? ` · ${e.email}` : ''}
                    <button
                      type="button"
                      className="ml-2 text-accent hover:underline"
                      onClick={() => startPhoneEdit(e)}
                    >
                      Edit
                    </button>
                  </p>
                )}
              </div>
            ),
          },
          { key: 'department', header: 'Department', render: (e) => e.department || '—' },
          {
            key: 'status',
            header: 'Status',
            render: (e) => <Badge variant={participationBadge(e.participation_status)}>{e.participation_status}</Badge>,
          },
          {
            key: 'onboarding',
            header: 'Onboarding',
            render: (e) => (
              <span className="text-xs text-text-secondary">
                {e.onboarding_step}
                {e.preferred_language ? ` · ${e.preferred_language}` : ''}
              </span>
            ),
          },
          {
            key: 'last_active',
            header: 'Last active',
            render: (e) => (e.last_active_at ? new Date(e.last_active_at).toLocaleString() : '—'),
          },
          {
            key: 'nudge',
            header: 'Last nudge',
            render: (e) => {
              const label = nudgeStatusLabel(e);
              if (!label) return '—';
              return (
                <span className="text-xs text-text-secondary">
                  {label}
                  {e.latest_nudge?.sent_at ? ` · ${new Date(e.latest_nudge.sent_at).toLocaleString()}` : ''}
                  {e.latest_nudge?.delivery_status === 'failed' && e.latest_nudge.error_message
                    ? ` · ${e.latest_nudge.error_message}`
                    : ''}
                </span>
              );
            },
          },
          {
            key: 'actions',
            header: '',
            render: (e) => (
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="secondary" onClick={() => setDigestEmployee(e)}>
                  Digest
                </Button>
                {e.can_nudge ? (
                  <Button
                    variant="secondary"
                    size="sm"
                    loading={nudgingId === e.id}
                    onClick={() => setNudgeConfirmEmployee(e)}
                  >
                    Nudge
                  </Button>
                ) : e.participation_status === 'started' && e.last_nudged_at ? (
                  <span className="text-xs text-text-secondary">Cooldown (24h)</span>
                ) : null}
              </div>
            ),
          },
        ]}
        rows={employees as Employee[]}
        emptyState={
          <EmptyState
            title="No employees yet"
            description="You can build a document baseline first, then invite employees later to strengthen the same signals."
          />
        }
      />

      <Modal
        open={nudgeConfirmEmployee != null}
        onClose={() => setNudgeConfirmEmployee(null)}
        title="Send nudge reminder?"
        footer={
          <>
            <Button variant="secondary" onClick={() => setNudgeConfirmEmployee(null)}>
              Cancel
            </Button>
            <Button
              loading={nudgeConfirmEmployee != null && nudgingId === nudgeConfirmEmployee.id}
              onClick={() => nudgeConfirmEmployee && sendNudge(nudgeConfirmEmployee.id)}
            >
              Send nudge
            </Button>
          </>
        }
      >
        {nudgeConfirmEmployee && (
          <div className="space-y-3 text-sm text-text-secondary">
            <p className="m-0">
              Send a reminder to{' '}
              <span className="font-medium text-text-primary">
                {nudgeConfirmEmployee.display_name || nudgeConfirmEmployee.phone_e164}
              </span>{' '}
              to continue their discovery interview?
            </p>
            <p className="m-0">
              Delivery: <span className="text-text-primary">{nudgeChannelsLabel(nudgeConfirmEmployee)}</span>
            </p>
            <p className="m-0 text-xs">Nudges are limited to once every 24 hours per employee.</p>
          </div>
        )}
      </Modal>

      <EmployeeDigestModal
        employee={digestEmployee}
        open={digestEmployee != null}
        onClose={() => setDigestEmployee(null)}
      />
    </div>
  );
}
