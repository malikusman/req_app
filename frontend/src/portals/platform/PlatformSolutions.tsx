import { useEffect, useState } from 'react';
import { api, type SolutionCatalogEntry } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Input, Select, Button, Badge, EmptyState } from '../../components/ui';

export function PlatformSolutions() {
  const token = usePlatformToken();
  const [solutions, setSolutions] = useState<SolutionCatalogEntry[]>([]);
  const [name, setName] = useState('');
  const [vendor, setVendor] = useState('');
  const [category, setCategory] = useState('automation');
  const [entityType, setEntityType] = useState('tool');
  const [keywords, setKeywords] = useState('');
  const [loading, setLoading] = useState(true);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editActive, setEditActive] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = () => {
    if (!token) return;
    api
      .platformSolutions(token)
      .then((d) => setSolutions(d.solutions))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const create = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    await api.createSolution(token, {
      name,
      vendor,
      category,
      entity_type: entityType,
      match_keywords: keywords.split(',').map((k) => k.trim()).filter(Boolean),
      tags: [category],
      active: true,
      published_at: new Date().toISOString(),
    });
    setName('');
    setVendor('');
    setKeywords('');
    load();
  };

  const startEdit = (solution: SolutionCatalogEntry) => {
    setEditingId(solution.id);
    setEditActive(solution.active);
  };

  const saveEdit = async (solution: SolutionCatalogEntry) => {
    if (!token) return;
    setSaving(true);
    try {
      await api.updateSolution(token, solution.id, { active: editActive });
      setEditingId(null);
      load();
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Solution catalog"
        description="Curated tools matched to discovery signals in recommendations."
      />

      <Card title="Add solution">
        <form onSubmit={create} className="grid gap-4 md:grid-cols-2">
          <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} required />
          <Input label="Vendor" value={vendor} onChange={(e) => setVendor(e.target.value)} />
          <Select
            label="Category"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            options={[
              { value: 'automation', label: 'automation' },
              { value: 'ai_agent', label: 'ai_agent' },
              { value: 'integration', label: 'integration' },
              { value: 'saas', label: 'saas' },
            ]}
          />
          <Select
            label="Entity type"
            value={entityType}
            onChange={(e) => setEntityType(e.target.value)}
            options={[
              { value: 'tool', label: 'tool' },
              { value: 'app', label: 'app' },
              { value: 'model', label: 'model' },
              { value: 'agent', label: 'agent' },
              { value: 'integration', label: 'integration' },
              { value: 'service', label: 'service' },
            ]}
          />
          <Input
            label="Match keywords (comma-separated)"
            value={keywords}
            onChange={(e) => setKeywords(e.target.value)}
            placeholder="invoice, excel, approval"
          />
          <div className="md:col-span-2">
            <Button type="submit">Add solution</Button>
          </div>
        </form>
      </Card>

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'name',
            header: 'Name',
            render: (s) => (
              <span>
                {s.name}
                {s.vendor ? <span className="text-text-secondary"> · {s.vendor}</span> : null}
              </span>
            ),
          },
          { key: 'category', header: 'Category' },
          {
            key: 'entity_type',
            header: 'Type',
            render: (s) => <span className="text-xs">{(s as { entity_type?: string }).entity_type || 'tool'}</span>,
          },
          {
            key: 'keywords',
            header: 'Keywords',
            render: (s) => <span className="text-xs text-text-secondary">{s.match_keywords.join(', ')}</span>,
          },
          {
            key: 'active',
            header: 'Active',
            render: (s) =>
              editingId === s.id ? (
                <Select
                  value={editActive ? 'yes' : 'no'}
                  onChange={(e) => setEditActive(e.target.value === 'yes')}
                  options={[
                    { value: 'yes', label: 'yes' },
                    { value: 'no', label: 'no' },
                  ]}
                />
              ) : (
                <Badge variant={s.active ? 'success' : 'neutral'}>{s.active ? 'yes' : 'no'}</Badge>
              ),
          },
          {
            key: 'actions',
            header: '',
            render: (s) =>
              editingId === s.id ? (
                <div className="flex gap-2">
                  <Button size="sm" loading={saving} onClick={() => saveEdit(s)}>
                    Save
                  </Button>
                  <Button size="sm" variant="secondary" onClick={() => setEditingId(null)}>
                    Cancel
                  </Button>
                </div>
              ) : (
                <Button size="sm" variant="secondary" onClick={() => startEdit(s)}>
                  Edit
                </Button>
              ),
          },
        ]}
        rows={solutions}
        emptyState={<EmptyState title="No solutions" description="Add tools to the catalog for recommendation matching." />}
      />
    </div>
  );
}
