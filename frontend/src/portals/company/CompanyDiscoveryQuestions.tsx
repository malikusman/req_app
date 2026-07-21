import { useEffect, useState } from 'react';
import { api, type DiscoveryQuestion } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, DataTable, Button, Badge, EmptyState } from '../../components/ui';

export function CompanyDiscoveryQuestions() {
  const token = useCompanyToken();
  const [questions, setQuestions] = useState<DiscoveryQuestion[]>([]);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .discoveryQuestions(token)
      .then((d) => setQuestions(d.questions))
      .catch(() => setLoadError('Could not load discovery questions.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const flag = async (messageId: number, feedback: string) => {
    if (!token) return;
    setError('');
    try {
      await api.discoveryQuestionFeedback(token, messageId, feedback);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed');
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Discovery questions"
        description="Questions employees receive during discovery — not their answers (privacy preserved)."
      />
      {error && <p className="text-sm text-status-error">{error}</p>}

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
            key: 'when',
            header: 'When',
            render: (q) => new Date(q.created_at).toLocaleDateString(),
          },
          {
            key: 'employee',
            header: 'Employee',
            render: (q) => (
              <div>
                <span>{q.employee.display_name || '—'}</span>
                <p className="m-0 text-xs text-text-secondary">{q.employee.department}</p>
              </div>
            ),
          },
          { key: 'body', header: 'Question', className: 'max-w-md' },
          {
            key: 'feedback',
            header: 'Feedback',
            render: (q) =>
              q.feedback ? (
                <Badge variant="neutral">{q.feedback.replace(/_/g, ' ')}</Badge>
              ) : (
                <div className="flex gap-2">
                  <Button variant="secondary" size="sm" onClick={() => flag(q.id, 'not_relevant')}>
                    Not relevant
                  </Button>
                  <Button variant="secondary" size="sm" onClick={() => flag(q.id, 'off_track')}>
                    Off-track
                  </Button>
                </div>
              ),
          },
        ]}
        rows={questions as DiscoveryQuestion[]}
        emptyState={<EmptyState title="No questions" description="Discovery questions appear as interviews progress." />}
      />
    </div>
  );
}
