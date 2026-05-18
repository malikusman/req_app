import { useEffect, useState, type FormEvent } from 'react';
import { api, type ReviewerUser } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';

export function PlatformReviewers() {
  const token = usePlatformToken();
  const [reviewers, setReviewers] = useState<ReviewerUser[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ email: '', name: '', password: 'password123' });
  const [error, setError] = useState('');

  const load = () => {
    if (!token) return;
    api.platformReviewers(token).then((d) => setReviewers(d.reviewers));
  };

  useEffect(() => {
    load();
  }, [token]);

  const handleCreate = async (e: FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    try {
      await api.createPlatformReviewer(token, form);
      setShowForm(false);
      setForm({ email: '', name: '', password: 'password123' });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed');
    }
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
        <h1 style={{ margin: 0 }}>Reviewers</h1>
        <button type="button" className="btn btn-primary" onClick={() => setShowForm(!showForm)}>
          {showForm ? 'Cancel' : 'New reviewer'}
        </button>
      </div>
      {showForm && (
        <div className="card" style={{ marginBottom: '1rem' }}>
          {error && <div className="error">{error}</div>}
          <form onSubmit={handleCreate}>
            <div className="form-group">
              <label>Email</label>
              <input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} required />
            </div>
            <div className="form-group">
              <label>Name</label>
              <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
            </div>
            <div className="form-group">
              <label>Password</label>
              <input type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} required />
            </div>
            <button type="submit" className="btn btn-primary">
              Create
            </button>
          </form>
        </div>
      )}
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {reviewers.map((r) => (
              <tr key={r.id}>
                <td>{r.name}</td>
                <td>{r.email}</td>
                <td>{r.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
