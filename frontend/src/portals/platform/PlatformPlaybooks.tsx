import { useEffect, useState } from 'react';
import { api, type Playbook } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';

const DEPARTMENTS = ['default', 'finance', 'sales', 'hr', 'operations', 'support', 'executive'];

export function PlatformPlaybooks() {
  const token = usePlatformToken();
  const [playbooks, setPlaybooks] = useState<Playbook[]>([]);
  const [department, setDepartment] = useState('operations');
  const [promptBlock, setPromptBlock] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  const load = () => {
    if (!token) return;
    api.platformPlaybooks(token).then((d) => setPlaybooks(d.playbooks));
  };

  useEffect(() => {
    load();
  }, [token]);

  const create = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    setMessage('');
    try {
      await api.createPlaybook(token, { department, prompt_block: promptBlock, notes: notes || undefined });
      setPromptBlock('');
      setNotes('');
      setMessage('Playbook version created. Activate it to use in discovery interviews.');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Create failed');
    }
  };

  const activate = async (id: number) => {
    if (!token) return;
    setError('');
    try {
      await api.activatePlaybook(token, id);
      setMessage('Playbook activated for its department.');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Activate failed');
    }
  };

  const byDepartment = DEPARTMENTS.map((dept) => ({
    dept,
    items: playbooks.filter((p) => p.department === dept),
  }));

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Discovery playbooks</h1>
      <p style={{ color: '#64748b' }}>
        Department playbooks are injected into the LangGraph agent at runtime. Activate a version without redeploying the agent.
      </p>

      {error && <div className="error">{error}</div>}
      {message && (
        <div style={{ background: '#d1fae5', color: '#065f46', padding: '0.75rem', borderRadius: 8, marginBottom: '1rem' }}>
          {message}
        </div>
      )}

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <h3 style={{ marginTop: 0 }}>New playbook version</h3>
        <form onSubmit={create}>
          <div className="form-group">
            <label>Department</label>
            <select value={department} onChange={(e) => setDepartment(e.target.value)}>
              {DEPARTMENTS.map((d) => (
                <option key={d} value={d}>
                  {d}
                </option>
              ))}
            </select>
          </div>
          <div className="form-group">
            <label>Prompt block</label>
            <textarea
              value={promptBlock}
              onChange={(e) => setPromptBlock(e.target.value)}
              required
              rows={6}
              placeholder="System instructions for discovery interviews in this department..."
              style={{ width: '100%' }}
            />
          </div>
          <div className="form-group">
            <label>Notes (internal)</label>
            <input value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
          <button type="submit" className="btn btn-primary">
            Create version
          </button>
        </form>
      </div>

      {byDepartment.map(({ dept, items }) => (
        <div className="card" key={dept} style={{ marginBottom: '1rem' }}>
          <h3 style={{ marginTop: 0, textTransform: 'capitalize' }}>{dept}</h3>
          {items.length === 0 ? (
            <p style={{ color: '#94a3b8' }}>No versions yet.</p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Version</th>
                  <th>Active</th>
                  <th>Updated</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {items.map((p) => (
                  <tr key={p.id}>
                    <td>v{p.version}</td>
                    <td>{p.active ? <span className="badge badge-completed">active</span> : '—'}</td>
                    <td>{new Date(p.updated_at).toLocaleString()}</td>
                    <td>
                      {!p.active && (
                        <button type="button" className="btn btn-secondary" onClick={() => activate(p.id)}>
                          Activate
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      ))}
    </div>
  );
}
