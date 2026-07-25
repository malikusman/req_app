import { useEffect, useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type ReviewerUser } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Button, DataTable, Input, Modal, Badge, EmptyState } from '../../components/ui';

function generatePassword() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(14));
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}

export function PlatformReviewers() {
  const token = usePlatformToken();
  const navigate = useNavigate();
  const [reviewers, setReviewers] = useState<ReviewerUser[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ email: '', name: '', password: generatePassword() });
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token) return;
    setLoading(true);
    api
      .platformReviewers(token)
      .then((d) => setReviewers(d.reviewers))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load reviewers'))
      .finally(() => setLoading(false));
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
      setForm({ email: '', name: '', password: generatePassword() });
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed');
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reviewers"
        description="Manage external reviewers assigned to client reports."
        actions={<Button onClick={() => setShowForm(true)}>New reviewer</Button>}
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <DataTable
        loading={loading}
        columns={[
          { key: 'name', header: 'Name' },
          { key: 'email', header: 'Email' },
          {
            key: 'profile',
            header: 'Profile',
            render: (r) => (
              <span className="text-sm text-text-secondary">
                {r.profile_completeness_percent ?? 0}%
                {r.profile_status === 'published' ? (
                  <Badge variant="success" className="ml-2">
                    published
                  </Badge>
                ) : (
                  <Badge variant="neutral" className="ml-2">
                    draft
                  </Badge>
                )}
              </span>
            ),
          },
          {
            key: 'headline',
            header: 'Headline',
            render: (r) => (
              <span className="max-w-[200px] truncate text-xs text-text-secondary">{r.headline || '—'}</span>
            ),
          },
          {
            key: 'status',
            header: 'Status',
            render: (r) => (
              <Badge variant={r.status === 'active' ? 'success' : 'neutral'}>{r.status}</Badge>
            ),
          },
        ]}
        rows={reviewers as ReviewerUser[]}
        onRowClick={(r) => navigate(`/platform/reviewers/${r.id}`)}
        emptyState={<EmptyState title="No reviewers" description="Create a reviewer account to assign to companies." />}
      />

      <Modal open={showForm} onClose={() => setShowForm(false)} title="New reviewer">
        <form onSubmit={handleCreate} className="space-y-4">
          {error && <p className="text-sm text-status-error">{error}</p>}
          <Input
            label="Email"
            type="email"
            value={form.email}
            onChange={(e) => setForm({ ...form, email: e.target.value })}
            required
          />
          <Input label="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
          <div className="space-y-1">
            <Input
              label="Password"
              type="text"
              value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              required
            />
            <p className="text-xs text-text-secondary">
              Share this with the reviewer — they use it for their first sign-in.
            </p>
          </div>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setShowForm(false)}>
              Cancel
            </Button>
            <Button type="submit">Create</Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
