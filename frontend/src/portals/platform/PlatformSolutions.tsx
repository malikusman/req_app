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
  const [keywords, setKeywords] = useState('');
  const [loading, setLoading] = useState(true);

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
      match_keywords: keywords.split(',').map((k) => k.trim()).filter(Boolean),
      tags: [category],
      active: true,
    });
    setName('');
    setVendor('');
    setKeywords('');
    load();
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
            key: 'keywords',
            header: 'Keywords',
            render: (s) => <span className="text-xs text-text-secondary">{s.match_keywords.join(', ')}</span>,
          },
          {
            key: 'active',
            header: 'Active',
            render: (s) => <Badge variant={s.active ? 'success' : 'neutral'}>{s.active ? 'yes' : 'no'}</Badge>,
          },
        ]}
        rows={solutions as SolutionCatalogEntry[]}
        emptyState={<EmptyState title="No solutions" description="Add tools to the catalog for recommendation matching." />}
      />
    </div>
  );
}
