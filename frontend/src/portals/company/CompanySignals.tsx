import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type CompanySignal } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, DataTable, Badge, StrengthBar, EmptyState, Button } from '../../components/ui';

export function CompanySignals() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [signals, setSignals] = useState<CompanySignal[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [docsFirst, setDocsFirst] = useState(false);

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .intelligenceSignals(token)
      .then((d) => setSignals(d.signals))
      .catch(() => setLoadError('Could not load signals.'))
      .finally(() => setLoading(false));
    api
      .companyDashboard(token)
      .then((d) => setDocsFirst(Boolean(d.docs_first_phase ?? d.company.docs_first_phase)))
      .catch(() => undefined);
  };

  useEffect(() => {
    load();
  }, [token]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Signals"
        description="Structured pain points and opportunities extracted from documents and discovery interviews."
      />

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'label',
            header: 'Signal',
            className: 'max-w-[280px]',
            render: (s) => (
              <div className="min-w-0 max-w-[280px] truncate" title={s.label}>
                {s.label}
              </div>
            ),
          },
          {
            key: 'strength',
            header: 'Strength',
            render: (s) => (
              <div className="min-w-[120px]">
                <StrengthBar strength={s.strength} />
                <span className="text-xs text-text-secondary">{Math.round(s.strength * 100)}%</span>
              </div>
            ),
          },
          {
            key: 'departments',
            header: 'Departments',
            className: 'max-w-[200px]',
            render: (s) => (
              <div className="min-w-0 max-w-[200px] truncate" title={s.departments.join(', ')}>
                {s.departments.join(', ') || '—'}
              </div>
            ),
          },
          {
            key: 'evidence',
            header: 'Evidence',
            render: (s) => s.evidence_count,
          },
          {
            key: 'status',
            header: 'Status',
            render: (s) => <Badge variant="info">{s.status}</Badge>,
          },
        ]}
        rows={signals as CompanySignal[]}
        emptyState={
          <EmptyState
            title="No signals yet"
            description={
              docsFirst
                ? 'Upload SOPs or finance exports to extract your first operational signals.'
                : 'Upload documents or complete interviews to surface operational signals.'
            }
            action={
              docsFirst
                ? { label: 'Upload documents', onClick: () => navigate('/company/documents') }
                : { label: 'Invite employees', onClick: () => navigate('/company/employees') }
            }
            secondaryAction={
              docsFirst
                ? { label: 'Invite employees', onClick: () => navigate('/company/employees') }
                : { label: 'Upload documents', onClick: () => navigate('/company/documents') }
            }
          />
        }
      />
    </div>
  );
}
