import { useEffect, useState } from 'react';
import { api, type Playbook } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import {
  PageHeader,
  Tabs,
  Card,
  Button,
  Textarea,
  Input,
  Select,
  DataTable,
  Badge,
  EmptyState,
} from '../../components/ui';

const DEPARTMENTS = ['default', 'finance', 'sales', 'hr', 'operations', 'support', 'executive'];

export function PlatformPlaybooks() {
  const token = usePlatformToken();
  const [playbooks, setPlaybooks] = useState<Playbook[]>([]);
  const [deptTab, setDeptTab] = useState('operations');
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

  const deptPlaybooks = playbooks.filter((p) => p.department === deptTab);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Discovery playbooks"
        description="Department playbooks are injected into the LangGraph agent at runtime."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}
      {message && (
        <p className="rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">{message}</p>
      )}

      <Card title="New playbook version">
        <form onSubmit={create} className="space-y-4">
          <Select
            label="Department"
            value={department}
            onChange={(e) => setDepartment(e.target.value)}
            options={DEPARTMENTS.map((d) => ({ value: d, label: d }))}
          />
          <Textarea
            label="Prompt block"
            value={promptBlock}
            onChange={(e) => setPromptBlock(e.target.value)}
            required
            rows={6}
            placeholder="System instructions for discovery interviews in this department..."
          />
          <Input label="Notes (internal)" value={notes} onChange={(e) => setNotes(e.target.value)} />
          <Button type="submit">Create version</Button>
        </form>
      </Card>

      <Tabs
        tabs={DEPARTMENTS.map((d) => ({ value: d, label: d.charAt(0).toUpperCase() + d.slice(1) }))}
        value={deptTab}
        onChange={setDeptTab}
      />

      <DataTable
        columns={[
          { key: 'version', header: 'Version', render: (p) => `v${p.version}` },
          {
            key: 'active',
            header: 'Active',
            render: (p) =>
              p.active ? <Badge variant="success">active</Badge> : <span className="text-text-secondary">—</span>,
          },
          {
            key: 'updated',
            header: 'Updated',
            render: (p) => new Date(p.updated_at).toLocaleString(),
          },
          {
            key: 'actions',
            header: '',
            render: (p) =>
              !p.active ? (
                <Button variant="secondary" size="sm" onClick={() => activate(p.id)}>
                  Activate
                </Button>
              ) : null,
          },
        ]}
        rows={deptPlaybooks as Playbook[]}
        emptyState={<EmptyState title="No versions" description={`No playbook versions for ${deptTab}.`} />}
      />
    </div>
  );
}
