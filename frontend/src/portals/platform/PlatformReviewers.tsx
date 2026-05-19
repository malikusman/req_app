import { useEffect, useState, type FormEvent } from 'react';
import { api, type ReviewerUser } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Button, DataTable, Input, Modal, Badge, EmptyState } from '../../components/ui';

export function PlatformReviewers() {
  const token = usePlatformToken();
  const [reviewers, setReviewers] = useState<ReviewerUser[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ email: '', name: '', password: 'password123' });
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token) return;
    api
      .platformReviewers(token)
      .then((d) => setReviewers(d.reviewers))
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
      setForm({ email: '', name: '', password: 'password123' });
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

      <DataTable
        loading={loading}
        columns={[
          { key: 'name', header: 'Name' },
          { key: 'email', header: 'Email' },
          {
            key: 'status',
            header: 'Status',
            render: (r) => (
              <Badge variant={r.status === 'active' ? 'success' : 'neutral'}>{r.status}</Badge>
            ),
          },
        ]}
        rows={reviewers as ReviewerUser[]}
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
          <Input
            label="Password"
            type="password"
            value={form.password}
            onChange={(e) => setForm({ ...form, password: e.target.value })}
            required
          />
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
