import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  api,
  type CompanyClarificationQuestion,
  type CompanyKnowledgeEntry,
} from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Badge, Button, Textarea, EmptyState } from '../../components/ui';

function statusVariant(status: string): 'info' | 'success' | 'warning' | 'error' | 'neutral' {
  if (status === 'open' || status === 'pending_rag') return 'warning';
  if (status === 'answered' || status === 'auto_answered') return 'success';
  if (status === 'dismissed_by_consultant' || status === 'stale') return 'neutral';
  return 'info';
}

export function CompanyKnowledge() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [entries, setEntries] = useState<CompanyKnowledgeEntry[]>([]);
  const [questions, setQuestions] = useState<CompanyClarificationQuestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [answers, setAnswers] = useState<Record<number, string>>({});
  const [savingId, setSavingId] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    setError('');
    Promise.all([api.companyKnowledgeEntries(token), api.companyClarificationQuestions(token)])
      .then(([kb, qs]) => {
        setEntries(kb.knowledge_entries);
        setQuestions(qs.clarification_questions);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Could not load knowledge'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const submitAnswer = async (id: number) => {
    if (!token) return;
    const answer = (answers[id] || '').trim();
    if (!answer) return;
    setSavingId(id);
    try {
      const { clarification_question } = await api.answerClarificationQuestion(token, id, answer);
      setQuestions((prev) => prev.map((q) => (q.id === id ? clarification_question : q)));
      setAnswers((prev) => ({ ...prev, [id]: '' }));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save answer');
    } finally {
      setSavingId(null);
    }
  };

  const openQuestions = questions.filter((q) => q.status === 'open' || q.status === 'pending_rag');
  const answeredQuestions = questions.filter((q) =>
    ['answered', 'auto_answered'].includes(q.status)
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Knowledge"
        description="What we've learned from your documents, and the gaps we're still filling."
        actions={
          <Link to="/company/documents">
            <Button variant="secondary" size="sm">
              Documents
            </Button>
          </Link>
        }
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <Card title="Gaps we're still filling">
        {loading ? (
          <p className="text-sm text-text-secondary">Loading…</p>
        ) : openQuestions.length === 0 ? (
          <EmptyState
            title="No open questions"
            description="Once we've read your documents, anything we still need to know shows up here for your team to answer."
          />
        ) : (
          <ul className="m-0 list-none space-y-4 p-0">
            {openQuestions.map((q) => (
              <li key={q.id} className="rounded-button border border-border p-4">
                <div className="mb-2 flex flex-wrap items-center gap-2">
                  <Badge variant={statusVariant(q.status)}>{q.status.replace(/_/g, ' ')}</Badge>
                </div>
                <p className="m-0 text-sm text-text-primary">{q.body}</p>
                <div className="mt-3 space-y-2">
                  <Textarea
                    value={answers[q.id] || ''}
                    onChange={(e) => setAnswers((prev) => ({ ...prev, [q.id]: e.target.value }))}
                    placeholder="Your answer…"
                    rows={3}
                  />
                  <Button
                    size="sm"
                    loading={savingId === q.id}
                    disabled={!(answers[q.id] || '').trim()}
                    onClick={() => submitAnswer(q.id)}
                  >
                    Submit answer
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="Answered questions">
        {answeredQuestions.length === 0 ? (
          <p className="m-0 text-sm text-text-secondary">Nothing answered yet.</p>
        ) : (
          <ul className="m-0 list-none space-y-3 p-0">
            {answeredQuestions.map((q) => (
              <li key={q.id} className="rounded-button border border-border p-4">
                <div className="mb-2 flex flex-wrap items-center gap-2">
                  <Badge variant={statusVariant(q.status)}>{q.status.replace(/_/g, ' ')}</Badge>
                  {q.answer_source && (
                    <span className="text-xs text-text-secondary">via {q.answer_source}</span>
                  )}
                </div>
                <p className="m-0 text-sm font-medium text-text-primary">{q.body}</p>
                <p className="mt-2 m-0 text-sm text-text-secondary">{q.answer}</p>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="What we've learned">
        {loading ? (
          <p className="text-sm text-text-secondary">Loading…</p>
        ) : entries.length === 0 ? (
          <EmptyState
            title="Nothing learned yet"
            description="Upload documents and we'll pull out what matters — you'll see it summarized here."
            action={{ label: 'Go to documents', onClick: () => navigate('/company/documents') }}
          />
        ) : (
          <ul className="m-0 list-none space-y-3 p-0">
            {entries.map((e) => (
              <li key={e.id} className="rounded-button border border-border p-4">
                <div className="mb-1 flex flex-wrap items-center gap-2">
                  <Badge variant="info">{e.entry_type}</Badge>
                  {e.department && <span className="text-xs text-text-secondary">{e.department}</span>}
                  <span className="text-xs text-text-secondary">
                    confidence {Math.round((e.confidence || 0) * 100)}%
                  </span>
                </div>
                <p className="m-0 text-sm font-medium text-text-primary">{e.title}</p>
                <p className="mt-1 m-0 text-sm text-text-secondary">{e.content}</p>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
