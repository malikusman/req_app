import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api, type Stage1QuoteStatus, type Stage1QuoteSummary } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { formatMoney, formatPercent } from '../../lib/money';
import { Badge, Button, DataTable, EmptyState, PageHeader, Tabs } from '../../components/ui';
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_VARIANTS } from './engagementStatus';

/** Which quotes each tab lists. */
const VIEWS: { value: string; label: string; statuses: Stage1QuoteStatus[] }[] = [
  { value: 'waiting', label: 'Waiting for approval', statuses: ['PROPOSED'] },
  { value: 'client', label: 'With the client', statuses: ['ISSUED'] },
  { value: 'accepted', label: 'Accepted', statuses: ['ACCEPTED'] },
  { value: 'closed', label: 'Declined, expired or sent back', statuses: ['DECLINED', 'EXPIRED', 'REJECTED'] },
];

function dateLabel(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

/**
 * The administrator's pricing queue (Doc 21 §26): every Stage 1 quote the
 * platform has proposed, waiting for approval, with the margin against the
 * floor visible at a glance.
 */
export function PlatformPricingQueue() {
  const token = usePlatformToken();
  const navigate = useNavigate();
  const [view, setView] = useState('waiting');
  const [rows, setRows] = useState<Stage1QuoteSummary[]>([]);
  const [waiting, setWaiting] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    const statuses = VIEWS.find((v) => v.value === view)?.statuses ?? ['PROPOSED'];
    setLoading(true);
    setError('');
    api
      .platformStage1Quotes(token, statuses)
      .then((d) => {
        setRows(d.quotes);
        setWaiting(d.proposed_count);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load the pricing queue'))
      .finally(() => setLoading(false));
  }, [token, view]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Pricing"
        description={
          waiting > 0
            ? `${waiting} Stage 1 quote${waiting === 1 ? ' is' : 's are'} waiting for your approval. No price reaches a client until it is approved.`
            : 'Stage 1 quotes the platform proposes wait here for approval. No price reaches a client until it is approved.'
        }
        actions={
          <Link to="/platform/pricing/rates">
            <Button variant="secondary" size="sm">
              Rates and margin floor
            </Button>
          </Link>
        }
      />

      <Tabs tabs={VIEWS.map(({ value, label }) => ({ value, label }))} value={view} onChange={setView} />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <DataTable
        loading={loading}
        onRowClick={(r) => navigate(`/platform/pricing/${r.id}`)}
        columns={[
          { key: 'company', header: 'Company', render: (r) => r.company_name },
          { key: 'version', header: 'Version', render: (r) => <span className="tabular-nums">v{r.version}</span> },
          {
            key: 'total',
            header: 'Total',
            render: (r) => <span className="tabular-nums">{formatMoney(r.total, r.currency)}</span>,
          },
          {
            key: 'scope',
            header: 'Covers',
            hideOnMobile: true,
            render: (r) => (
              <span className="text-sm text-text-secondary">
                {r.participants_included} people · {r.deep_dives_included} deep dives
              </span>
            ),
          },
          {
            key: 'margin',
            header: 'Margin',
            render: (r) =>
              r.below_floor ? (
                <Badge variant="error">{formatPercent(r.margin_percent)} · below floor</Badge>
              ) : (
                <span className="tabular-nums">{formatPercent(r.margin_percent)}</span>
              ),
          },
          {
            key: 'status',
            header: 'Status',
            render: (r) => <Badge variant={QUOTE_STATUS_VARIANTS[r.status]}>{QUOTE_STATUS_LABELS[r.status]}</Badge>,
          },
          {
            key: 'date',
            header: view === 'waiting' ? 'Proposed' : 'Issued',
            hideOnMobile: true,
            render: (r) => (
              <span className="tabular-nums text-text-secondary">
                {dateLabel(view === 'waiting' ? r.created_at : r.issued_at)}
              </span>
            ),
          },
        ]}
        rows={rows}
        emptyState={
          <EmptyState
            title={view === 'waiting' ? "You're all caught up" : 'Nothing here'}
            description={
              view === 'waiting'
                ? 'No Stage 1 quotes are waiting for approval.'
                : 'No Stage 1 quotes are in this state.'
            }
          />
        }
      />
    </div>
  );
}
