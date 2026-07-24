import { useEffect, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import {
  api,
  type AgenticIdea,
  type CompanyPattern,
  type CompanySignal,
  type Recommendation,
  type TimelineEvent,
} from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import {
  PageHeader,
  Card,
  StatCard,
  DataTable,
  Badge,
  StrengthBar,
  EmptyState,
  Button,
  Skeleton,
  Timeline,
} from '../../components/ui';
import { useToast } from '../../components/ui/ToastProvider';
import { FileBarChart, Radio, Shapes, Lightbulb } from 'lucide-react';

const FEEDBACK_LABELS: Record<string, string> = {
  interested: 'Interested',
  already_doing: 'Already doing this',
  not_relevant: 'Not relevant',
};

type Tab = 'overview' | 'signals' | 'patterns' | 'recommendations' | 'timeline';

function tabFromHash(hash: string): Tab {
  const h = hash.replace(/^#/, '');
  if (h === 'signals' || h === 'patterns' || h === 'recommendations' || h === 'timeline') return h;
  return 'overview';
}

export function CompanyIntelligence() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const location = useLocation();
  const { toast } = useToast();
  const [tab, setTab] = useState<Tab>(() => tabFromHash(location.hash));
  const [signals, setSignals] = useState<CompanySignal[]>([]);
  const [patterns, setPatterns] = useState<CompanyPattern[]>([]);
  const [recs, setRecs] = useState<Recommendation[]>([]);
  const [ideas, setIdeas] = useState<AgenticIdea[]>([]);
  const [events, setEvents] = useState<TimelineEvent[]>([]);
  const [readiness, setReadiness] = useState(0);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');

  useEffect(() => {
    setTab(tabFromHash(location.hash));
  }, [location.hash]);

  const load = () => {
    if (!token) return;
    setLoadError('');
    setLoading(true);
    Promise.all([
      api.intelligenceSignals(token),
      api.intelligencePatterns(token),
      api.companyRecommendations(token).catch(() => ({ recommendations: [] as Recommendation[] })),
      api.companyAgenticIdeas(token).catch(() => ({ agentic_ideas: [] as AgenticIdea[] })),
      api.intelligenceTimeline(token).catch(() => ({ events: [] as TimelineEvent[] })),
      api.companyDashboard(token).catch(() => null),
    ])
      .then(([sig, pat, rec, idea, tl, dash]) => {
        setSignals(sig.signals);
        setPatterns(pat.patterns);
        setRecs(rec.recommendations);
        setIdeas(idea.agentic_ideas);
        setEvents(tl.events);
        if (dash) setReadiness(Math.round(dash.report_readiness_score ?? 0));
      })
      .catch(() => setLoadError('Could not load intelligence.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const selectTab = (next: Tab) => {
    setTab(next);
    navigate(next === 'overview' ? '/company/intelligence' : `/company/intelligence#${next}`, { replace: true });
  };

  const submitFeedback = async (id: number, feedback: string) => {
    if (!token) return;
    try {
      await api.recommendationFeedback(token, id, feedback);
      const d = await api.companyRecommendations(token);
      setRecs(d.recommendations);
      toast({ variant: 'success', title: 'Feedback saved', description: 'Thanks — this helps rank future recommendations.' });
    } catch (err) {
      toast({
        variant: 'error',
        title: 'Feedback failed',
        description: err instanceof Error ? err.message : 'Could not save feedback.',
      });
    }
  };

  const tabs: { id: Tab; label: string }[] = [
    { id: 'overview', label: 'Overview' },
    { id: 'signals', label: 'Signals' },
    { id: 'patterns', label: 'Patterns' },
    { id: 'recommendations', label: 'Recommendations' },
    { id: 'timeline', label: 'Timeline' },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Intelligence"
        description="Signals, patterns, and recommendations from documents and discovery interviews."
      />

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <div className="flex flex-wrap gap-2 border-b border-border pb-3">
        {tabs.map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => selectTab(t.id)}
            className={`rounded-button px-3 py-1.5 text-sm ${
              tab === t.id
                ? 'bg-primary text-primary-foreground'
                : 'text-muted-foreground hover:bg-muted hover:text-foreground'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="space-y-4">
          <Skeleton variant="text" />
          <Skeleton variant="card" />
        </div>
      ) : (
        <>
          {(tab === 'overview' || tab === 'signals') && (
            <div className={tab === 'overview' ? 'space-y-6' : 'hidden'}>
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <StatCard label="Readiness" value={`${readiness}%`} icon={<FileBarChart className="h-5 w-5 text-primary" />} />
                <StatCard label="Signals" value={signals.length} icon={<Radio className="h-5 w-5 text-primary" />} />
                <StatCard label="Patterns" value={patterns.length} icon={<Shapes className="h-5 w-5 text-primary" />} />
                <StatCard
                  label="Recommendations"
                  value={recs.length + ideas.length}
                  icon={<Lightbulb className="h-5 w-5 text-primary" />}
                />
              </div>
            </div>
          )}

          {(tab === 'overview' || tab === 'signals') && (
            <section id="signals" className="space-y-3">
              {tab === 'overview' ? (
                <div className="flex items-center justify-between gap-2">
                  <h2 className="m-0 text-lg font-medium text-foreground">Signals</h2>
                  <Button size="sm" variant="secondary" onClick={() => selectTab('signals')}>
                    View all
                  </Button>
                </div>
              ) : null}
              <DataTable
                columns={[
                  {
                    key: 'label',
                    header: 'Signal',
                    className: 'max-w-[280px]',
                    render: (s: CompanySignal) => (
                      <div className="min-w-0 max-w-[280px] truncate" title={s.label}>
                        {s.label}
                      </div>
                    ),
                  },
                  {
                    key: 'strength',
                    header: 'Strength',
                    render: (s: CompanySignal) => (
                      <div className="min-w-[120px]">
                        <StrengthBar strength={s.strength} />
                        <span className="text-xs text-text-secondary">{Math.round(s.strength * 100)}%</span>
                      </div>
                    ),
                  },
                  {
                    key: 'departments',
                    header: 'Departments',
                    render: (s: CompanySignal) => s.departments.join(', ') || '—',
                  },
                  {
                    key: 'evidence',
                    header: 'Evidence',
                    render: (s: CompanySignal) => s.evidence_count,
                  },
                  {
                    key: 'status',
                    header: 'Status',
                    render: (s: CompanySignal) => <Badge variant="info">{s.status}</Badge>,
                  },
                ]}
                rows={(tab === 'overview' ? signals.slice(0, 5) : signals) as CompanySignal[]}
                emptyState={
                  <EmptyState
                    title="No signals yet"
                    description="Upload documents or complete interviews to surface operational signals."
                    action={{ label: 'Upload documents', onClick: () => navigate('/company/documents') }}
                  />
                }
              />
            </section>
          )}

          {(tab === 'overview' || tab === 'patterns') && (
            <section id="patterns" className="space-y-3">
              {tab === 'overview' ? (
                <div className="flex items-center justify-between gap-2">
                  <h2 className="m-0 text-lg font-medium text-foreground">Patterns</h2>
                  <Button size="sm" variant="secondary" onClick={() => selectTab('patterns')}>
                    View all
                  </Button>
                </div>
              ) : null}
              {patterns.length === 0 ? (
                <EmptyState
                  title="No patterns yet"
                  description="Patterns emerge as signals strengthen across departments."
                  action={{ label: 'Upload documents', onClick: () => navigate('/company/documents') }}
                />
              ) : (
                <div className="grid gap-4 md:grid-cols-2">
                  {(tab === 'overview' ? patterns.slice(0, 4) : patterns).map((p) => (
                    <Card key={p.id}>
                      <div className="flex items-start justify-between gap-2">
                        <h3 className="m-0 font-medium text-text-primary">{p.title}</h3>
                        <Badge variant="info">{Math.round(p.confidence * 100)}%</Badge>
                      </div>
                      {p.description && <p className="mt-2 text-sm text-text-secondary">{p.description}</p>}
                      <p className="mt-2 text-xs text-text-secondary">{p.departments.join(', ') || 'All departments'}</p>
                      <Badge variant="neutral" className="mt-2">
                        {p.status}
                      </Badge>
                    </Card>
                  ))}
                </div>
              )}
            </section>
          )}

          {(tab === 'overview' || tab === 'recommendations') && (
            <section id="recommendations" className="space-y-3">
              {tab === 'overview' ? (
                <div className="flex items-center justify-between gap-2">
                  <h2 className="m-0 text-lg font-medium text-foreground">Recommendations</h2>
                  <Button size="sm" variant="secondary" onClick={() => selectTab('recommendations')}>
                    View all
                  </Button>
                </div>
              ) : null}

              {ideas.length > 0 && tab !== 'overview' && (
                <div className="space-y-3">
                  <h3 className="m-0 text-base font-medium text-foreground">Published agentic ideas</h3>
                  {ideas.map((idea) => (
                    <Card key={idea.id}>
                      <div className="mb-2 flex flex-wrap items-center gap-2">
                        <h3 className="m-0 font-medium text-text-primary">{idea.title}</h3>
                        <Badge variant="success">{Math.round((idea.confidence || 0) * 100)}% confidence</Badge>
                      </div>
                      {idea.summary && <p className="text-sm text-text-secondary">{idea.summary}</p>}
                    </Card>
                  ))}
                </div>
              )}

              {recs.length === 0 && ideas.length === 0 ? (
                <EmptyState
                  title="No recommendations"
                  description="Upload documents or complete discovery interviews so recommendations can be synthesized."
                  action={{ label: 'Upload documents', onClick: () => navigate('/company/documents') }}
                />
              ) : (
                (tab === 'overview' ? recs.slice(0, 3) : recs).map((r) => (
                  <Card key={r.id}>
                    <div className="mb-2 flex items-center gap-2">
                      <h3 className="m-0 font-medium text-text-primary">{r.title}</h3>
                      <Badge variant={r.priority === 'high' ? 'warning' : 'info'}>{r.priority}</Badge>
                    </div>
                    {r.description && <p className="text-sm text-text-secondary">{r.description}</p>}
                    {tab !== 'overview' && (
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
                    )}
                  </Card>
                ))
              )}
            </section>
          )}

          {(tab === 'overview' || tab === 'timeline') && (
            <section id="timeline" className="space-y-3">
              {tab === 'overview' ? (
                <div className="flex items-center justify-between gap-2">
                  <h2 className="m-0 text-lg font-medium text-foreground">Recent activity</h2>
                  <Button size="sm" variant="secondary" onClick={() => selectTab('timeline')}>
                    View all
                  </Button>
                </div>
              ) : null}
              {events.length === 0 ? (
                <EmptyState title="No timeline events yet" description="Activity appears as discovery progresses." />
              ) : (
                <Card>
                  <Timeline
                    events={(tab === 'overview' ? events.slice(0, 5) : events).map((e, i) => ({
                      id: String(e.id ?? i),
                      title: e.title,
                      summary: e.summary,
                      occurredAt: e.occurred_at,
                    }))}
                  />
                </Card>
              )}
            </section>
          )}

          {tab === 'overview' && (
            <p className="text-sm text-muted-foreground">
              Need billing, meetings, or WhatsApp tools?{' '}
              <Link to="/company/settings" className="font-medium text-primary hover:underline">
                Open Settings
              </Link>
            </p>
          )}
        </>
      )}
    </div>
  );
}
