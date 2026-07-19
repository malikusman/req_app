import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type CompanySignal } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, DataTable, Badge, StrengthBar, EmptyState } from '../../components/ui';

export function CompanySignals() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [signals, setSignals] = useState<CompanySignal[]>([]);
  const [loading, setLoading] = useState(true);
  const [docsFirst, setDocsFirst] = useState(false);

  useEffect(() => {
    if (!token) return;
    api
      .intelligenceSignals(token)
      .then((d) => setSignals(d.signals))
      .finally(() => setLoading(false));
    api.companyDashboard(token).then((d) => setDocsFirst(Boolean(d.docs_first_phase ?? d.company.docs_first_phase)));
  }, [token]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Signals"
        description="Structured pain points and opportunities extracted from documents and discovery interviews."
      />

      <DataTable
        loading={loading}
        columns={[
          { key: 'label', header: 'Signal' },
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
            render: (s) => s.departments.join(', ') || '—',
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
            action={{
              label: docsFirst ? 'Upload documents' : 'Upload documents',
              onClick: () => navigate('/company/documents'),
            }}
            secondaryAction={
              docsFirst
                ? { label: 'Invite employees', onClick: () => navigate('/company/employees') }
                : { label: 'View employees', onClick: () => navigate('/company/employees') }
            }
          />
        }
      />
    </div>
  );
}
