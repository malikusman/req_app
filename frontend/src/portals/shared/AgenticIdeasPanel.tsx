import { useEffect, useState } from 'react';
import { api, type AgenticIdea } from '../../lib/api';
import { Badge, Button, Card, EmptyState, Input, Skeleton, Textarea } from '../../components/ui';

type Mode = 'platform' | 'reviewer';

type Notice = { kind: 'success' | 'error'; text: string };

export function AgenticIdeasPanel({
  token,
  companyId,
  mode,
}: {
  token: string;
  companyId: number;
  mode: Mode;
}) {
  const [ideas, setIdeas] = useState<AgenticIdea[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [synthesizing, setSynthesizing] = useState(false);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [title, setTitle] = useState('');
  const [summary, setSummary] = useState('');
  const [systemFit, setSystemFit] = useState('');
  const [timeline, setTimeline] = useState('4–8 weeks');
  const [estimatedCost, setEstimatedCost] = useState('');
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editDraft, setEditDraft] = useState<Partial<AgenticIdea>>({});

  const load = () => {
    setLoading(true);
    const req =
      mode === 'platform'
        ? api.platformAgenticIdeas(token, companyId)
        : api.reviewerAgenticIdeas(token, companyId);
    req
      .then((d) => setIdeas(d.agentic_ideas))
      .catch((err) =>
        setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Failed to load ideas' })
      )
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token, companyId, mode]);

  const create = async () => {
    if (!title.trim()) return;
    setCreating(true);
    setNotice(null);
    try {
      const payload = {
        title: title.trim(),
        summary: summary.trim() || undefined,
        system_fit: systemFit.trim() || undefined,
        approx_timeline: timeline.trim() || undefined,
        estimated_cost: estimatedCost.trim() || undefined,
        status: 'draft',
      };
      if (mode === 'platform') await api.createPlatformAgenticIdea(token, companyId, payload);
      else await api.createReviewerAgenticIdea(token, companyId, payload);
      setTitle('');
      setSummary('');
      setSystemFit('');
      setEstimatedCost('');
      setNotice({ kind: 'success', text: 'Idea added as draft.' });
      load();
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Create failed' });
    } finally {
      setCreating(false);
    }
  };

  const publish = async (id: number) => {
    setBusyId(id);
    try {
      if (mode === 'platform') await api.publishPlatformAgenticIdea(token, companyId, id);
      else await api.publishReviewerAgenticIdea(token, companyId, id);
      load();
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Publish failed' });
    } finally {
      setBusyId(null);
    }
  };

  const archive = async (id: number) => {
    if (mode !== 'platform') return;
    setBusyId(id);
    try {
      await api.archivePlatformAgenticIdea(token, companyId, id);
      load();
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Archive failed' });
    } finally {
      setBusyId(null);
    }
  };

  const synthesize = async () => {
    if (mode !== 'platform') return;
    setSynthesizing(true);
    setNotice(null);
    try {
      const d = await api.synthesizePlatformAgenticIdeas(token, companyId);
      setIdeas(d.agentic_ideas);
      setNotice({ kind: 'success', text: `Generated ${d.synthesized} draft ideas from company evidence.` });
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Synthesize failed' });
    } finally {
      setSynthesizing(false);
    }
  };

  const saveEdit = async (id: number) => {
    setBusyId(id);
    try {
      if (mode === 'platform') await api.updatePlatformAgenticIdea(token, companyId, id, editDraft);
      else await api.updateReviewerAgenticIdea(token, companyId, id, editDraft);
      setEditingId(null);
      setEditDraft({});
      load();
    } catch (err) {
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Update failed' });
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="m-0 text-sm text-muted-foreground">
          Living backlog of agentic opportunities. Only <strong>published</strong> ideas enter the next generated PDF.
        </p>
        {mode === 'platform' && (
          <Button size="sm" variant="secondary" loading={synthesizing} onClick={synthesize}>
            Generate from evidence
          </Button>
        )}
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
        <Skeleton variant="card" />
      ) : ideas.length === 0 ? (
        <EmptyState title="No agentic ideas yet" description="Generate from evidence or add one manually." />
      ) : (
        <ul className="m-0 list-none space-y-3 p-0">
          {ideas.map((idea) => (
            <li key={idea.id} className="rounded-md border border-border px-3 py-3">
              {editingId === idea.id ? (
                <div className="space-y-2">
                  <Input
                    label="Title"
                    value={editDraft.title ?? idea.title}
                    onChange={(e) => setEditDraft((d) => ({ ...d, title: e.target.value }))}
                  />
                  <Textarea
                    label="Summary"
                    rows={2}
                    value={editDraft.summary ?? idea.summary ?? ''}
                    onChange={(e) => setEditDraft((d) => ({ ...d, summary: e.target.value }))}
                  />
                  <Textarea
                    label="System fit"
                    rows={2}
                    value={editDraft.system_fit ?? idea.system_fit ?? ''}
                    onChange={(e) => setEditDraft((d) => ({ ...d, system_fit: e.target.value }))}
                  />
                  <div className="grid gap-2 md:grid-cols-2">
                    <Input
                      label="Timeline"
                      value={editDraft.approx_timeline ?? idea.approx_timeline ?? ''}
                      onChange={(e) => setEditDraft((d) => ({ ...d, approx_timeline: e.target.value }))}
                    />
                    <Input
                      label="Estimated cost (optional)"
                      value={editDraft.estimated_cost ?? idea.estimated_cost ?? ''}
                      onChange={(e) => setEditDraft((d) => ({ ...d, estimated_cost: e.target.value }))}
                    />
                  </div>
                  <div className="flex gap-2">
                    <Button size="sm" loading={busyId === idea.id} onClick={() => saveEdit(idea.id)}>
                      Save
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => setEditingId(null)}>
                      Cancel
                    </Button>
                  </div>
                </div>
              ) : (
                <>
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <h4 className="m-0 text-sm font-medium">{idea.title}</h4>
                        <Badge variant={idea.status === 'published' ? 'success' : 'info'}>{idea.status}</Badge>
                        <Badge variant="neutral">{idea.source}</Badge>
                      </div>
                      {idea.summary && <p className="mt-1 mb-0 text-sm text-muted-foreground">{idea.summary}</p>}
                      {idea.system_fit && (
                        <p className="mt-1 mb-0 text-xs text-muted-foreground">
                          <strong>Fit:</strong> {idea.system_fit}
                        </p>
                      )}
                      <p className="mt-1 mb-0 text-xs text-muted-foreground">
                        {idea.approx_timeline || 'Timeline TBD'}
                        {idea.estimated_cost ? ` · ${idea.estimated_cost}` : ''}
                        {` · ${Math.round((idea.confidence || 0) * 100)}% confidence`}
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <Button
                        size="sm"
                        variant="secondary"
                        onClick={() => {
                          setEditingId(idea.id);
                          setEditDraft({
                            title: idea.title,
                            summary: idea.summary ?? '',
                            system_fit: idea.system_fit ?? '',
                            approx_timeline: idea.approx_timeline ?? '',
                            estimated_cost: idea.estimated_cost ?? '',
                          });
                        }}
                      >
                        Edit
                      </Button>
                      {idea.status !== 'published' && (
                        <Button size="sm" loading={busyId === idea.id} onClick={() => publish(idea.id)}>
                          Publish
                        </Button>
                      )}
                      {mode === 'platform' && idea.status !== 'archived' && (
                        <Button size="sm" variant="secondary" loading={busyId === idea.id} onClick={() => archive(idea.id)}>
                          Archive
                        </Button>
                      )}
                    </div>
                  </div>
                </>
              )}
            </li>
          ))}
        </ul>
      )}

      <Card title="Add idea">
        <div className="space-y-3">
          <Input label="Title" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Approval copilot for freight exceptions" />
          <Textarea label="Summary" rows={2} value={summary} onChange={(e) => setSummary(e.target.value)} />
          <Textarea
            label="How it fits current systems"
            rows={2}
            value={systemFit}
            onChange={(e) => setSystemFit(e.target.value)}
          />
          <div className="grid gap-3 md:grid-cols-2">
            <Input label="Approx timeline" value={timeline} onChange={(e) => setTimeline(e.target.value)} />
            <Input
              label="Estimated cost (optional)"
              value={estimatedCost}
              onChange={(e) => setEstimatedCost(e.target.value)}
              placeholder="e.g. $15–25k"
            />
          </div>
          <Button size="sm" loading={creating} disabled={!title.trim()} onClick={create}>
            Add draft idea
          </Button>
        </div>
      </Card>
    </div>
  );
}
