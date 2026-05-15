import { useEffect, useState } from 'react';
import { api, type Employee } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanyEmployees() {
  const token = useCompanyToken();
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [phone, setPhone] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [department, setDepartment] = useState('');
  const [newCode, setNewCode] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [nudgeMsg, setNudgeMsg] = useState('');

  const load = () => {
    if (!token) return;
    api.companyEmployees(token).then((d) => setEmployees(d.employees));
  };

  useEffect(() => {
    load();
  }, [token]);

  const invite = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    setNewCode(null);
    try {
      const res = await api.inviteEmployee(token, phone, displayName || undefined, department || undefined);
      setNewCode(res.access_code);
      setPhone('');
      setDisplayName('');
      setDepartment('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Invite failed');
    }
  };

  const sendNudge = async (employeeId: number) => {
    if (!token) return;
    setNudgeMsg('');
    setError('');
    try {
      await api.nudgeEmployee(token, employeeId);
      setNudgeMsg('Nudge sent via WhatsApp.');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Nudge failed');
    }
  };

  const copyCode = (code: string) => {
    navigator.clipboard.writeText(code);
  };

  const statusBadge = (status: string) => `badge badge-${status}`;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Employees</h1>
      <p style={{ color: '#64748b' }}>
        Invite employees via WhatsApp. Share access codes privately — they are never included in the template message.
      </p>

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <h3 style={{ marginTop: 0 }}>Invite employee</h3>
        {error && <div className="error">{error}</div>}
        {nudgeMsg && <div style={{ background: '#d1fae5', color: '#065f46', padding: '0.75rem', borderRadius: 8, marginBottom: '1rem' }}>{nudgeMsg}</div>}
        {newCode && (
          <div style={{ marginBottom: '1rem' }}>
            <p style={{ margin: '0 0 0.5rem' }}>Access code (copy and share privately):</p>
            <div className="code-box">{newCode}</div>
            <button type="button" className="btn btn-secondary" style={{ marginTop: '0.5rem' }} onClick={() => copyCode(newCode)}>
              Copy code
            </button>
          </div>
        )}
        <form onSubmit={invite}>
          <div className="form-group">
            <label>Phone E.164</label>
            <input value={phone} onChange={(e) => setPhone(e.target.value)} required placeholder="+14155551234" />
          </div>
          <div className="form-group">
            <label>Name</label>
            <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
          </div>
          <div className="form-group">
            <label>Department</label>
            <input value={department} onChange={(e) => setDepartment(e.target.value)} />
          </div>
          <button type="submit" className="btn btn-primary">
            Send WhatsApp invite
          </button>
        </form>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Participation funnel</h3>
        <table>
          <thead>
            <tr>
              <th>Employee</th>
              <th>Department</th>
              <th>Status</th>
              <th>Onboarding</th>
              <th>Last active</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {employees.map((e) => (
              <tr key={e.id}>
                <td>
                  {e.display_name || '—'}
                  {e.stalled && (
                    <span className="badge" style={{ marginLeft: 8, background: '#fef3c7', color: '#92400e' }}>
                      stalled
                    </span>
                  )}
                  <br />
                  <small>{e.phone_e164}</small>
                </td>
                <td>{e.department || '—'}</td>
                <td>
                  <span className={statusBadge(e.participation_status)}>{e.participation_status}</span>
                </td>
                <td>
                  <small>{e.onboarding_step}</small>
                  {e.preferred_language && <br />}
                  {e.preferred_language && <small>lang: {e.preferred_language}</small>}
                </td>
                <td>{e.last_active_at ? new Date(e.last_active_at).toLocaleString() : '—'}</td>
                <td>
                  {e.can_nudge && (
                    <button type="button" className="btn btn-secondary" onClick={() => sendNudge(e.id)}>
                      Nudge
                    </button>
                  )}
                  {e.last_nudged_at && !e.can_nudge && e.participation_status === 'started' && (
                    <small style={{ color: '#94a3b8' }}>Nudged recently</small>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {employees.length === 0 && <p style={{ color: '#64748b' }}>No employees invited yet.</p>}
      </div>
    </div>
  );
}
