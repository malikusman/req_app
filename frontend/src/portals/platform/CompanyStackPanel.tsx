import { useEffect, useState } from 'react';
import { api, type CompanySystemRow } from '../../lib/api';
import { Badge, Button, Card, EmptyState, Input, Select, Skeleton } from '../../components/ui';

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

type Notice = { kind: 'success' | 'error'; text: string };

export function CompanyStackPanel({ token, companyId }: { token: string; companyId: number }) {
  const [systems, setSystems] = useState<CompanySystemRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [inferring, setInferring] = useState(false);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [name, setName] = useState('');
  const [category, setCategory] = useState('other');

  const load = () => {
    setLoading(true);
    api
      .platformCompanySystems(token, companyId)
      .then((d) => setSystems(d.company_systems.filter((s) => s.active)))
      .catch((err) =>
        setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Failed to load stack' })
      )
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  const create = async () => {
    if (!name.trim()) return;
    setCreating(true);
    try {
      await api.createPlatformCompanySystem(token, companyId, { name: name.trim(), category });
      setName('');
      load();
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Create failed' });
    } finally {
      setCreating(false);
    }
  };

  const infer = async () => {
    setInferring(true);
    setNotice(null);
    try {
      const d = await api.inferPlatformCompanySystems(token, companyId);
      setSystems(d.company_systems.filter((s) => s.active));
      setNotice({
        kind: 'success',
        text: `Inferred/updated ${d.inferred} stack entries from employees and documents.`,
      });
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Infer failed' });
    } finally {
      setInferring(false);
    }
  };

  const deactivate = async (id: number) => {
    setBusyId(id);
    try {
      await api.updatePlatformCompanySystem(token, companyId, id, { active: false });
      load();
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="m-0 text-sm text-muted-foreground">
          Client systems already in use — used for catalog fit and agentic idea system-fit narratives.
        </p>
        <Button size="sm" variant="secondary" loading={inferring} onClick={infer}>
          Infer from evidence
        </Button>
      </div>
      {notice &&
        (notice.kind === 'success' ? (
          <p className="m-0 rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">
            {notice.text}
          </p>
        ) : (
          <p className="m-0 text-sm text-status-error">{notice.text}</p>
        ))}
      {loading ? (
        <div className="space-y-2">
          <Skeleton variant="text" />
          <Skeleton variant="text" className="w-2/3" />
        </div>
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
              <Button size="sm" variant="secondary" loading={busyId === s.id} onClick={() => deactivate(s.id)}>
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
            <Button size="sm" loading={creating} disabled={!name.trim()} onClick={create}>
              Add
            </Button>
          </div>
        </div>
      </Card>
    </div>
  );
}
