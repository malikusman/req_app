import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type AgenticIdea, type Recommendation } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Button, Badge, EmptyState, Skeleton } from '../../components/ui';

const FEEDBACK_LABELS: Record<string, string> = {
  interested: 'Interested',
  already_doing: 'Already doing this',
  not_relevant: 'Not relevant',
};

export function CompanyRecommendations() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [recs, setRecs] = useState<Recommendation[]>([]);
  const [ideas, setIdeas] = useState<AgenticIdea[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    Promise.all([
      api.companyRecommendations(token),
      api.companyAgenticIdeas(token).catch(() => ({ agentic_ideas: [] as AgenticIdea[] })),
    ])
      .then(([recData, ideaData]) => {
        setRecs(recData.recommendations);
        setIdeas(ideaData.agentic_ideas);
      })
      .finally(() => setLoading(false));
  }, [token]);

  const submitFeedback = async (id: number, feedback: string) => {
    if (!token) return;
    await api.recommendationFeedback(token, id, feedback);
    const d = await api.companyRecommendations(token);
    setRecs(d.recommendations);
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Recommendations"
        description="Ranked opportunities from your signals and patterns, plus published agentic ideas for your company."
      />

      {ideas.length > 0 && (
        <div className="space-y-3">
          <h2 className="m-0 text-lg font-medium text-foreground">Published agentic ideas</h2>
          {ideas.map((idea) => (
            <Card key={idea.id}>
              <div className="mb-2 flex flex-wrap items-center gap-2">
                <h3 className="m-0 font-medium text-text-primary">{idea.title}</h3>
                <Badge variant="success">
                  {Math.round((idea.confidence || 0) * 100)}% confidence
                </Badge>
              </div>
              {idea.summary && <p className="text-sm text-text-secondary">{idea.summary}</p>}
              {idea.system_fit && (
                <p className="text-sm text-text-primary">
                  <strong>System fit:</strong> {idea.system_fit}
                </p>
              )}
              <p className="text-xs text-muted-foreground">
                {[idea.approx_timeline, idea.estimated_cost, idea.catalog_name].filter(Boolean).join(' · ')}
              </p>
            </Card>
          ))}
        </div>
      )}

      {recs.length === 0 ? (
        <EmptyState
          title="No recommendations"
          description="Upload documents or complete discovery interviews so recommendations can be synthesized."
          action={{ label: 'Upload documents', onClick: () => navigate('/company/documents') }}
          secondaryAction={{ label: 'Invite employees', onClick: () => navigate('/company/employees') }}
        />
      ) : (
        recs.map((r) => (
          <Card key={r.id}>
            <div className="mb-2 flex items-center gap-2">
              <h3 className="m-0 font-medium text-text-primary">{r.title}</h3>
              <Badge variant={r.priority === 'high' ? 'warning' : 'info'}>{r.priority}</Badge>
            </div>
            {r.description && <p className="text-sm text-text-secondary">{r.description}</p>}
            {r.implementation_outline && (
              <p className="text-sm text-text-primary">{r.implementation_outline}</p>
            )}
            {r.catalog_matches?.length > 0 && (
              <div className="mt-3">
                <p className="text-sm font-medium text-text-primary">Suggested tools</p>
                <ul className="mt-1 list-inside list-disc text-sm text-text-secondary">
                  {r.catalog_matches.map((c, i) => (
                    <li key={i}>
                      {c.name}
                      {c.vendor ? ` (${c.vendor})` : ''}
                      {'score' in c && c.score != null
                        ? ` · ${Math.round(Number(c.score) <= 1 ? Number(c.score) * 100 : Number(c.score))}% fit`
                        : ''}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <div className="mt-4 flex flex-wrap gap-2">
              {(['interested', 'already_doing', 'not_relevant'] as const).map((f) => (
                <Button
                  key={f}
                  variant={r.company_feedback === f ? 'primary' : 'secondary'}
                  size="sm"
                  onClick={() => submitFeedback(r.id, f)}
                >
                  {FEEDBACK_LABELS[f] ?? f}
                </Button>
              ))}
            </div>
          </Card>
        ))
      )}
    </div>
  );
}
