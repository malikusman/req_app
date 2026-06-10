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
} from '../../components/ui';

function participationBadge(status: string) {
  if (status === 'completed') return 'success' as const;
  if (status === 'started') return 'info' as const;
  if (status === 'invited') return 'warning' as const;
  return 'neutral' as const;
}

export function CompanyEmployees() {
  const token = useCompanyToken();
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [phone, setPhone] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [department, setDepartment] = useState('');
  const [newCode, setNewCode] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [nudgeMsg, setNudgeMsg] = useState('');
  const [loading, setLoading] = useState(true);
  const [inviting, setInviting] = useState(false);
  const [nudgingId, setNudgingId] = useState<number | null>(null);
  const [editingPhoneId, setEditingPhoneId] = useState<number | null>(null);
  const [editPhone, setEditPhone] = useState('');
  const [savingPhone, setSavingPhone] = useState(false);

  const load = () => {
    if (!token) return;
    api
      .companyEmployees(token)
      .then((d) => setEmployees(d.employees))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
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
      const res = await api.inviteEmployee(token, phone, displayName || undefined, department || undefined);
      setNewCode(res.access_code);
      setPhone('');
      setDisplayName('');
      setDepartment('');
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
      await api.nudgeEmployee(token, employeeId);
      setNudgeMsg('Nudge sent via WhatsApp.');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Nudge failed');
    } finally {
      setNudgingId(null);
    }
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
        description="Invite employees via WhatsApp. Share access codes privately — never in the template message."
      />

      <Card title="Invite employee">
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
        <form onSubmit={invite} className="grid gap-4 md:grid-cols-3">
          <Input
            label="Phone E.164"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            required
            placeholder="+14155551234"
          />
          <Input label="Name" value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
          <Input label="Department" value={department} onChange={(e) => setDepartment(e.target.value)} />
          <div className="md:col-span-3">
            <Button type="submit" loading={inviting}>
              Send WhatsApp invite
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
            key: 'actions',
            header: '',
            render: (e) =>
              e.can_nudge ? (
                <Button
                  variant="secondary"
                  size="sm"
                  loading={nudgingId === e.id}
                  onClick={() => sendNudge(e.id)}
                >
                  Nudge
                </Button>
              ) : e.last_nudged_at && e.participation_status === 'started' ? (
                <span className="text-xs text-text-secondary">Nudged recently</span>
              ) : null,
          },
        ]}
        rows={employees as Employee[]}
        emptyState={<EmptyState title="No employees" description="Invite your first employee to start discovery." />}
      />
    </div>
  );
}
