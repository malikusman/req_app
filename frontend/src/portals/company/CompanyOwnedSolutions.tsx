import { useCallback, useEffect, useState } from 'react';
import { api, type OwnedSolution } from '@/lib/api';
import { useCompanyToken } from '@/lib/auth';
import { PageHeader, Button, Card, Input, Textarea, Select, EmptyState, Badge } from '@/components/ui';
import { useToast } from '@/components/ui/ToastProvider';

const CATEGORIES = [
  { value: 'other', label: 'Other / in-house' },
  { value: 'erp', label: 'ERP' },
  { value: 'crm', label: 'CRM' },
  { value: 'finance', label: 'Finance' },
  { value: 'messaging', label: 'Messaging' },
  { value: 'tms', label: 'TMS / logistics' },
  { value: 'warehouse', label: 'Warehouse' },
  { value: 'spreadsheet', label: 'Spreadsheet' },
];

const EMPTY = { name: '', category: 'other', description: '', capabilities: '' };

export function CompanyOwnedSolutions() {
  const token = useCompanyToken();
  const { toast } = useToast();
  const [solutions, setSolutions] = useState<OwnedSolution[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [form, setForm] = useState({ ...EMPTY });
  const [editingId, setEditingId] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    if (!token) return;
    setLoading(true);
    setLoadError(false);
    try {
      const data = await api.companyOwnedSolutions(token);
      setSolutions(data.owned_solutions);
    } catch {
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    load();
  }, [load]);

  const resetForm = () => {
    setForm({ ...EMPTY });
    setEditingId(null);
  };

  const submit = async () => {
    if (!token || !form.name.trim()) return;
    setSaving(true);
    try {
      if (editingId) {
        await api.updateCompanyOwnedSolution(token, editingId, form);
      } else {
        await api.createCompanyOwnedSolution(token, form);
      }
      toast({ variant: 'success', title: editingId ? 'Updated' : 'Added', description: 'Included in your next report.' });
      resetForm();
      await load();
    } catch (e) {
      toast({ variant: 'error', title: 'Could not save', description: e instanceof Error ? e.message : 'Try again.' });
    } finally {
      setSaving(false);
    }
  };

  const edit = (s: OwnedSolution) => {
    setEditingId(s.id);
    setForm({
      name: s.name,
      category: s.category,
      description: s.description ?? '',
      capabilities: s.capabilities ?? '',
    });
  };

  const remove = async (id: number) => {
    if (!token) return;
    await api.deleteCompanyOwnedSolution(token, id);
    if (editingId === id) resetForm();
    await load();
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Owned solutions"
        description="Tell reviewers what you've already built or bought — in-house AI, apps, or tools. We score how well each addresses the frictions we find, and it appears in your report."
      />

      <Card title={editingId ? 'Edit solution' : 'Add a solution you already own'}>
        <div className="space-y-4">
          <Input
            label="Name"
            placeholder="e.g. In-house HR onboarding copilot"
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            required
          />
          <Select
            label="Type"
            value={form.category}
            onChange={(e) => setForm({ ...form, category: e.target.value })}
            options={CATEGORIES}
          />
          <Textarea
            label="What does it do?"
            placeholder="Describe what it automates or handles, in your own words."
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
            rows={3}
          />
          <Textarea
            label="Key capabilities (optional)"
            placeholder="e.g. onboarding automation, document generation, employee Q&A"
            value={form.capabilities}
            onChange={(e) => setForm({ ...form, capabilities: e.target.value })}
            rows={2}
          />
          <div className="flex justify-end gap-2">
            {editingId && (
              <Button variant="secondary" onClick={resetForm}>
                Cancel
              </Button>
            )}
            <Button onClick={submit} loading={saving} disabled={saving || !form.name.trim()}>
              {editingId ? 'Save changes' : 'Add solution'}
            </Button>
          </div>
        </div>
      </Card>

      {loadError ? (
        <Card>
          <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
            Couldn't load your solutions.{' '}
            <Button variant="secondary" size="sm" onClick={load}>
              Retry
            </Button>
          </div>
        </Card>
      ) : loading ? (
        <Card>
          <p className="text-sm text-text-secondary">Loading…</p>
        </Card>
      ) : solutions.length === 0 ? (
        <EmptyState
          title="No owned solutions yet"
          description="Add the AI, apps, or tools you've already built or bought so reviewers can factor them into recommendations."
        />
      ) : (
        <div className="space-y-3">
          {solutions.map((s) => (
            <Card key={s.id}>
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-text-primary">{s.name}</span>
                    <Badge>{s.category}</Badge>
                    {s.reviewer_endorsed && <Badge variant="success">Reviewer-endorsed</Badge>}
                  </div>
                  {s.description && <p className="mt-1 text-sm text-text-secondary">{s.description}</p>}
                  {s.capabilities && <p className="mt-1 text-xs text-text-secondary">Capabilities: {s.capabilities}</p>}
                  {s.reviewer_note && (
                    <p className="mt-2 rounded-md bg-surface-muted px-2 py-1 text-xs text-text-secondary">
                      Reviewer: {s.reviewer_note}
                    </p>
                  )}
                </div>
                <div className="flex shrink-0 gap-2">
                  <Button variant="ghost" size="sm" onClick={() => edit(s)}>
                    Edit
                  </Button>
                  <Button variant="ghost" size="sm" onClick={() => remove(s.id)}>
                    Remove
                  </Button>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
