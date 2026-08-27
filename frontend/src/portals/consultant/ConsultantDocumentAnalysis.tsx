import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  api,
  type CompanyClarificationQuestion,
  type CompanyKnowledgeEntry,
  type DocumentAnalysisEvent,
  type DocumentAnalysisRun,
} from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import { PageHeader, Card, Badge, Button, EmptyState, Skeleton } from '../../components/ui';

function statusVariant(status: string): 'info' | 'success' | 'warning' | 'error' | 'neutral' {
  if (status === 'open' || status === 'pending_rag') return 'warning';
  if (status === 'answered' || status === 'auto_answered') return 'success';
  if (status === 'dismissed_by_consultant') return 'neutral';
  return 'info';
}

export function ConsultantDocumentAnalysis() {
  const { companyId } = useParams();
  const token = useConsultantToken();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [latestRun, setLatestRun] = useState<DocumentAnalysisRun | null>(null);
  const [events, setEvents] = useState<DocumentAnalysisEvent[]>([]);
  const [entries, setEntries] = useState<CompanyKnowledgeEntry[]>([]);
  const [questions, setQuestions] = useState<CompanyClarificationQuestion[]>([]);
  const [dismissingId, setDismissingId] = useState<number | null>(null);

  const load = () => {
    if (!token || !companyId) return;
    setLoading(true);
    setError('');
    api
      .consultantDocumentAnalysis(token, Number(companyId))
      .then((d) => {
        setLatestRun(d.latest_run);
        setEvents(d.events);
        setEntries(d.knowledge_entries);
        setQuestions(d.clarification_questions);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load analysis'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  const dismiss = async (id: number) => {
    if (!token || !companyId) return;
    setDismissingId(id);
    try {
      const { clarification_question } = await api.dismissClarificationQuestion(
        token,
        Number(companyId),
        id
      );
      setQuestions((prev) => prev.map((q) => (q.id === id ? clarification_question : q)));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Dismiss failed');
    } finally {
      setDismissingId(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Document analysis"
        description="Pipeline run trace, knowledge base, and clarification questions for this company."
        breadcrumbs={[
          { label: 'Dashboard', href: '/consultant/dashboard' },
          { label: 'Company', href: `/consultant/companies/${companyId}` },
          { label: 'Analysis' },
        ]}
        actions={
          <Link to={`/consultant/companies/${companyId}/documents`}>
            <Button variant="secondary" size="sm">
              Documents
            </Button>
          </Link>
        }
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <Card title="Latest run">
        {!latestRun ? (
          <EmptyState
            title="No analysis yet"
            description="The company admin has not run document analysis."
          />
        ) : (
          <div className="space-y-2 text-sm">
            <p className="m-0">
              Run #{latestRun.id} · <Badge variant="info">{latestRun.run_kind}</Badge>{' '}
              <Badge
                variant={
                  latestRun.status.startsWith('completed')
                    ? 'success'
                    : latestRun.status === 'failed'
                      ? 'error'
                      : 'warning'
                }
              >
                {latestRun.status}
              </Badge>
            </p>
            {latestRun.summary && (
              <p className="m-0 text-text-secondary">
                Knowledge: {String((latestRun.summary as Record<string, unknown>).knowledge_count ?? '—')} ·
                Open questions: {String((latestRun.summary as Record<string, unknown>).open_questions ?? '—')}
              </p>
            )}
          </div>
        )}
      </Card>

      <Card title="Pipeline timeline">
        {events.length === 0 ? (
          <p className="m-0 text-sm text-text-secondary">No events recorded.</p>
        ) : (
          <ol className="m-0 list-none space-y-2 p-0">
            {events.map((e) => (
              <li key={e.id} className="border-l-2 border-border pl-3 text-sm">
                <span className="font-medium text-text-primary">{e.agent_name}</span>
                <span className="text-text-secondary"> · {e.event_type}</span>
                {e.message && <p className="m-0 mt-0.5 text-text-secondary">{e.message}</p>}
              </li>
            ))}
          </ol>
        )}
      </Card>

      <Card title="Knowledge base">
        {entries.length === 0 ? (
          <p className="m-0 text-sm text-text-secondary">No active knowledge entries.</p>
        ) : (
          <ul className="m-0 list-none space-y-3 p-0">
            {entries.map((e) => (
              <li key={e.id} className="rounded-button border border-border p-3">
                <div className="mb-1 flex flex-wrap gap-2">
                  <Badge variant="info">{e.entry_type}</Badge>
                  {e.department && <span className="text-xs text-text-secondary">{e.department}</span>}
                </div>
                <p className="m-0 text-sm font-medium">{e.title}</p>
                <p className="mt-1 m-0 text-sm text-text-secondary">{e.content}</p>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="Clarification questions">
        {questions.length === 0 ? (
          <p className="m-0 text-sm text-text-secondary">No questions.</p>
        ) : (
          <ul className="m-0 list-none space-y-3 p-0">
            {questions.map((q) => (
              <li key={q.id} className="rounded-button border border-border p-3">
                <div className="mb-2 flex flex-wrap items-center gap-2">
                  <Badge variant={statusVariant(q.status)}>{q.status.replace(/_/g, ' ')}</Badge>
                  {q.answer_source && (
                    <span className="text-xs text-text-secondary">via {q.answer_source}</span>
                  )}
                </div>
                <p className="m-0 text-sm font-medium">{q.body}</p>
                {q.answer && <p className="mt-1 m-0 text-sm text-text-secondary">{q.answer}</p>}
                {(q.status === 'open' || q.status === 'pending_rag') && (
                  <div className="mt-2">
                    <Button
                      size="sm"
                      variant="secondary"
                      loading={dismissingId === q.id}
                      onClick={() => dismiss(q.id)}
                    >
                      Dismiss as unnecessary
                    </Button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
