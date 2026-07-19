import { useEffect, useState } from 'react';
import { api, type CompanySystemRow } from '../../lib/api';
import { Badge, Button, Card, EmptyState, Input, Select } from '../../components/ui';

const CATEGORIES = [
  { value: 'erp', label: 'ERP' },
  { value: 'spreadsheet', label: 'Spreadsheet' },
  { value: 'tms', label: 'TMS' },
  { value: 'messaging', label: 'Messaging' },
  { value: 'crm', label: 'CRM' },
  { value: 'finance', label: 'Finance' },
  { value: 'warehouse', label: 'Warehouse' },
  { value: 'other', label: 'Other' },
];

export function CompanyStackPanel({ token, companyId }: { token: string; companyId: number }) {
  const [systems, setSystems] = useState<CompanySystemRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [name, setName] = useState('');
  const [category, setCategory] = useState('other');

  const load = () => {
    setLoading(true);
    api
      .platformCompanySystems(token, companyId)
      .then((d) => setSystems(d.company_systems.filter((s) => s.active)))
      .catch((err) => setMessage(err instanceof Error ? err.message : 'Failed to load stack'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  const create = async () => {
    if (!name.trim()) return;
    setSaving(true);
    try {
      await api.createPlatformCompanySystem(token, companyId, { name: name.trim(), category });
      setName('');
      load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Create failed');
    } finally {
      setSaving(false);
    }
  };

  const infer = async () => {
    setSaving(true);
    setMessage('');
    try {
      const d = await api.inferPlatformCompanySystems(token, companyId);
      setSystems(d.company_systems.filter((s) => s.active));
      setMessage(`Inferred/updated ${d.inferred} stack entries from employees and documents.`);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Infer failed');
    } finally {
      setSaving(false);
    }
  };

  const deactivate = async (id: number) => {
    setSaving(true);
    try {
      await api.updatePlatformCompanySystem(token, companyId, id, { active: false });
      load();
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="m-0 text-sm text-muted-foreground">
          Client systems already in use — used for catalog fit and agentic idea system-fit narratives.
        </p>
        <Button size="sm" variant="secondary" loading={saving} onClick={infer}>
          Infer from evidence
        </Button>
      </div>
      {message && <p className="m-0 text-sm text-muted-foreground">{message}</p>}
      {loading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : systems.length === 0 ? (
        <EmptyState title="No systems on file" description="Infer from documents/employees or add manually." />
      ) : (
        <ul className="m-0 list-none space-y-2 p-0">
          {systems.map((s) => (
            <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border px-3 py-2">
              <div>
                <span className="text-sm font-medium">{s.name}</span>
                <div className="mt-1 flex gap-2">
                  <Badge variant="neutral">{s.category}</Badge>
                  <Badge variant="info">{s.source}</Badge>
                </div>
              </div>
              <Button size="sm" variant="secondary" loading={saving} onClick={() => deactivate(s.id)}>
                Remove
              </Button>
            </li>
          ))}
        </ul>
      )}
      <Card title="Add system">
        <div className="grid gap-3 md:grid-cols-[1fr_160px_auto]">
          <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} placeholder="SAP" />
          <Select label="Category" value={category} onChange={(e) => setCategory(e.target.value)} options={CATEGORIES} />
          <div className="flex items-end">
            <Button size="sm" loading={saving} disabled={!name.trim()} onClick={create}>
              Add
            </Button>
          </div>
        </div>
      </Card>
    </div>
  );
}
