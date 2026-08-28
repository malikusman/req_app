import { useState, type FormEvent } from 'react';
import { AlertTriangle, Check, Lightbulb, MessageCircleQuestion, Send, X } from 'lucide-react';
import type {
  ConsultantRequirement,
  DiscoveryFollowupQuestion,
  DiscoveryPackage,
  DiscoveryPackageItem,
} from '../../../lib/api';
import { api } from '../../../lib/api';
import { useConsultantToken } from '../../../lib/auth';
import { Badge, Button, Card, EmptyState, Input, Textarea } from '../../../components/ui';
import { useToast } from '../../../components/ui/ToastProvider';
import { cn } from '../../../lib/cn';

const IMPACT_TONE: Record<string, 'error' | 'warning' | 'neutral'> = {
  high: 'error',
  medium: 'warning',
  low: 'neutral',
};

const REQUIREMENT_TONE: Record<string, 'success' | 'warning' | 'info' | 'neutral'> = {
  satisfied: 'success',
  partially_satisfied: 'warning',
  questions_drafted: 'info',
  open: 'info',
  withdrawn: 'neutral',
};

const REQUIREMENT_LABEL: Record<string, string> = {
  open: 'Drafting questions',
  questions_drafted: 'Questions ready',
  partially_satisfied: 'Answered, not settled',
  satisfied: 'Settled',
  withdrawn: 'Withdrawn',
};

/** An issue or solution: accept it, reword it, or reject it. */
function ItemRow({
  item,
  linkedTitle,
  onSave,
  onReject,
  busy,
}: {
  item: DiscoveryPackageItem;
  linkedTitle?: string | null;
  onSave: (body: string) => void;
  onReject: () => void;
  busy: boolean;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(item.body);

  return (
    <li
      className={cn(
        'rounded-lg border border-border bg-muted/30 px-3 py-2',
        item.status === 'rejected' && 'opacity-55'
      )}
    >
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="text-sm font-medium text-foreground">{item.title || 'Untitled'}</span>
        <span className="flex shrink-0 items-center gap-1.5">
          {item.impact && <Badge variant={IMPACT_TONE[item.impact]}>{item.impact} impact</Badge>}
          {item.origin === 'consultant' && <Badge variant="info">yours</Badge>}
          {item.status === 'amended' && <Badge variant="warning">amended</Badge>}
          {item.status === 'rejected' && <Badge variant="neutral">rejected</Badge>}
        </span>
      </div>

      {editing ? (
        <div className="mt-2 space-y-2">
          <Textarea value={draft} onChange={(e) => setDraft(e.target.value)} rows={3} />
          <div className="flex gap-2">
            <Button
              size="sm"
              disabled={!draft.trim() || busy}
              onClick={() => {
                onSave(draft.trim());
                setEditing(false);
              }}
            >
              Save
            </Button>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => {
                setDraft(item.body);
                setEditing(false);
              }}
            >
              Cancel
            </Button>
          </div>
        </div>
      ) : (
        <>
          <p className="m-0 mt-1 text-sm text-muted-foreground">{item.body}</p>
          {linkedTitle && (
            <p className="m-0 mt-1 text-xs text-muted-foreground">Addresses: {linkedTitle}</p>
          )}
          {item.status !== 'rejected' && (
            <div className="mt-2 flex gap-2">
              <Button size="sm" variant="secondary" onClick={() => setEditing(true)}>
                Reword
              </Button>
              <Button size="sm" variant="secondary" disabled={busy} onClick={onReject}>
                Reject
              </Button>
            </div>
          )}
        </>
      )}
    </li>
  );
}

function QuestionRow({
  question,
  isNext,
  canSend,
  onSend,
  onSkip,
  busy,
}: {
  question: DiscoveryFollowupQuestion;
  isNext: boolean;
  canSend: boolean;
  onSend: () => void;
  onSkip: () => void;
  busy: boolean;
}) {
  const pending = question.status === 'drafted' || question.status === 'queued';

  return (
    <li className="rounded-lg border border-border bg-muted/30 px-3 py-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="text-sm text-foreground">{question.body}</span>
        <span className="flex shrink-0 items-center gap-1.5">
          {isNext && pending && <Badge variant="info">next</Badge>}
          {question.from_parked_aside && <Badge variant="neutral">from an aside</Badge>}
          {!pending && <Badge variant="neutral">{question.status}</Badge>}
        </span>
      </div>
      {question.rationale && (
        <p className="m-0 mt-1 text-xs text-muted-foreground">{question.rationale}</p>
      )}
      {pending && (
        <div className="mt-2 flex flex-wrap gap-2">
          <Button
            size="sm"
            disabled={busy || !canSend}
            onClick={onSend}
            icon={<Send className="h-3.5 w-3.5" />}
          >
            Ask this
          </Button>
          <Button size="sm" variant="secondary" disabled={busy} onClick={onSkip}>
            Skip
          </Button>
        </div>
      )}
    </li>
  );
}

function RequirementCard({
  requirement,
  questions,
  onSatisfy,
  onWithdraw,
  busy,
}: {
  requirement: ConsultantRequirement;
  questions: DiscoveryFollowupQuestion[];
  onSatisfy: () => void;
  onWithdraw: () => void;
  busy: boolean;
}) {
  const open = !['satisfied', 'withdrawn'].includes(requirement.status);

  return (
    <li className="rounded-lg border border-border bg-card px-3 py-2.5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="text-sm font-medium text-foreground">“{requirement.statement}”</span>
        <Badge variant={REQUIREMENT_TONE[requirement.status]}>
          {REQUIREMENT_LABEL[requirement.status]}
        </Badge>
      </div>

      <p className="m-0 mt-1 text-xs tabular-nums text-muted-foreground">
        {requirement.questions_asked} of {requirement.max_questions} questions asked
        {requirement.consultant_name && ` · raised by ${requirement.consultant_name}`}
        {requirement.satisfaction_basis === 'consultant_manual' && ' · closed by you'}
      </p>

      {requirement.missing_aspects.length > 0 && open && (
        <p className="m-0 mt-1.5 text-xs text-warning">
          Still missing: {requirement.missing_aspects.join('; ')}
        </p>
      )}

      {questions.length > 0 && (
        <ul className="m-0 mt-2 list-none space-y-1 p-0">
          {questions.map((q) => (
            <li key={q.id} className="text-xs text-muted-foreground">
              <span className="tabular-nums">{q.status === 'answered' ? '✓' : '·'}</span> {q.body}
            </li>
          ))}
        </ul>
      )}

      {open && (
        <div className="mt-2 flex flex-wrap gap-2">
          <Button
            size="sm"
            variant="secondary"
            disabled={busy}
            onClick={onSatisfy}
            icon={<Check className="h-3.5 w-3.5" />}
          >
            Mark settled
          </Button>
          <Button
            size="sm"
            variant="secondary"
            disabled={busy}
            onClick={onWithdraw}
            icon={<X className="h-3.5 w-3.5" />}
          >
            Withdraw
          </Button>
        </div>
      )}
    </li>
  );
}

/**
 * The Discovery handover: the consultant amends the substance, and states what else
 * they need to know.
 *
 * They never write question text. The composer takes what they need in their own
 * words and the agent drafts questions from it — so one stated need can take several
 * questions, and the system can tell when the need is actually met.
 */
export function ConsultantDiscoveryPackagePanel({
  pkg,
  employeeName,
  onChanged,
}: {
  pkg: DiscoveryPackage | null;
  employeeName: string | null;
  onChanged: () => void;
}) {
  const token = useConsultantToken();
  const { toast } = useToast();
  const [busy, setBusy] = useState(false);
  const [statement, setStatement] = useState('');
  const [recDraft, setRecDraft] = useState<string | null>(null);
  const [newIssue, setNewIssue] = useState('');

  const run = async (label: string, fn: () => Promise<unknown>) => {
    if (!token || !pkg) return;
    setBusy(true);
    try {
      await fn();
      onChanged();
    } catch (err) {
      toast({
        variant: 'error',
        title: label,
        description: err instanceof Error ? err.message : 'Something went wrong.',
      });
    } finally {
      setBusy(false);
    }
  };

  if (!pkg) {
    return (
      <Card title="Discovery handover">
        <EmptyState
          title="No handover yet"
          description="It is assembled when the interview finishes. If the interview has completed, generation may still be running."
        />
      </Card>
    );
  }

  if (pkg.status === 'failed') {
    return (
      <Card title="Discovery handover">
        <p className="m-0 text-sm text-status-error">
          This handover could not be assembled{pkg.error_message ? `: ${pkg.error_message}` : '.'} The
          interview and its transcript are unaffected — use Source evidence in the meantime.
        </p>
      </Card>
    );
  }

  const issueTitleById = new Map(pkg.issues.map((i) => [i.id, i.title]));
  const questionsByRequirement = new Map<number, DiscoveryFollowupQuestion[]>();
  const unattached: DiscoveryFollowupQuestion[] = [];
  for (const q of pkg.followup_questions) {
    if (q.consultant_requirement_id == null) {
      unattached.push(q);
    } else {
      const list = questionsByRequirement.get(q.consultant_requirement_id) ?? [];
      list.push(q);
      questionsByRequirement.set(q.consultant_requirement_id, list);
    }
  }
  const firstPendingId = pkg.followup_questions.find(
    (q) => q.status === 'drafted' || q.status === 'queued'
  )?.id;
  const canSend = pkg.followup_budget_remaining > 0;

  return (
    <Card title="Discovery handover">
      <div className="space-y-5">
        <p className="m-0 -mt-1 text-sm text-muted-foreground">
          What the interview with {employeeName || 'this employee'} concluded · v{pkg.version}
        </p>

        {pkg.built_without_model && (
          <p className="m-0 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2 text-xs text-warning">
            Assembled directly from the interview without a language model, so it carries issues but no
            proposed solutions. Treat the confidence as low.
          </p>
        )}

        {/* Recommendation */}
        <div>
          <p className="m-0 mb-1 text-label-caps text-muted-foreground">Recommendation</p>
          {recDraft === null ? (
            <>
              <p className="m-0 text-sm font-medium text-foreground">
                {pkg.recommendation || 'No recommendation was produced.'}
              </p>
              {pkg.recommendation_rationale && (
                <p className="m-0 mt-1 text-sm text-muted-foreground">{pkg.recommendation_rationale}</p>
              )}
              <div className="mt-2 flex flex-wrap items-center gap-3">
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => setRecDraft(pkg.recommendation ?? '')}
                >
                  Rewrite
                </Button>
                {pkg.confidence != null && (
                  <span className="text-xs tabular-nums text-muted-foreground">
                    Agent confidence {Math.round(pkg.confidence * 100)}%
                  </span>
                )}
              </div>
            </>
          ) : (
            <div className="space-y-2">
              <Textarea value={recDraft} onChange={(e) => setRecDraft(e.target.value)} rows={3} />
              <p className="m-0 text-xs text-muted-foreground">
                The agent&apos;s original is kept, so this is never destructive.
              </p>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  disabled={busy || !recDraft.trim()}
                  onClick={() =>
                    run('Could not save the recommendation', async () => {
                      await api.amendDiscoveryPackage(token!, pkg.id, { recommendation: recDraft.trim() });
                      setRecDraft(null);
                    })
                  }
                >
                  Save
                </Button>
                <Button size="sm" variant="secondary" onClick={() => setRecDraft(null)}>
                  Cancel
                </Button>
              </div>
            </div>
          )}
        </div>

        {/* Issues */}
        <div>
          <p className="m-0 mb-2 flex items-center gap-1.5 text-label-caps text-muted-foreground">
            <AlertTriangle className="h-3.5 w-3.5" /> Issues ({pkg.issues.length})
          </p>
          {pkg.issues.length === 0 ? (
            <p className="m-0 text-sm text-muted-foreground">No issues were identified.</p>
          ) : (
            <ul className="m-0 list-none space-y-2 p-0">
              {pkg.issues.map((item) => (
                <ItemRow
                  key={item.id}
                  item={item}
                  busy={busy}
                  onSave={(body) =>
                    run('Could not save the issue', () =>
                      api.updateDiscoveryPackageItem(token!, pkg.id, item.id, { body })
                    )
                  }
                  onReject={() =>
                    run('Could not reject the issue', () =>
                      api.updateDiscoveryPackageItem(token!, pkg.id, item.id, { status: 'rejected' })
                    )
                  }
                />
              ))}
            </ul>
          )}

          <form
            className="mt-2 flex flex-wrap items-start gap-2"
            onSubmit={(e: FormEvent) => {
              e.preventDefault();
              if (!newIssue.trim()) return;
              run('Could not add the issue', async () => {
                await api.createDiscoveryPackageItem(token!, pkg.id, {
                  kind: 'issue',
                  body: newIssue.trim(),
                });
                setNewIssue('');
              });
            }}
          >
            <Input
              value={newIssue}
              onChange={(e) => setNewIssue(e.target.value)}
              placeholder="Add an issue the agent missed"
              className="min-w-0 flex-1"
            />
            <Button type="submit" size="sm" variant="secondary" disabled={busy || !newIssue.trim()}>
              Add
            </Button>
          </form>
        </div>

        {/* Solutions */}
        <div>
          <p className="m-0 mb-2 flex items-center gap-1.5 text-label-caps text-muted-foreground">
            <Lightbulb className="h-3.5 w-3.5" /> Possible solutions ({pkg.solutions.length})
          </p>
          {pkg.solutions.length === 0 ? (
            <p className="m-0 text-sm text-muted-foreground">None proposed.</p>
          ) : (
            <ul className="m-0 list-none space-y-2 p-0">
              {pkg.solutions.map((item) => (
                <ItemRow
                  key={item.id}
                  item={item}
                  busy={busy}
                  linkedTitle={item.linked_item_id ? issueTitleById.get(item.linked_item_id) : null}
                  onSave={(body) =>
                    run('Could not save the solution', () =>
                      api.updateDiscoveryPackageItem(token!, pkg.id, item.id, { body })
                    )
                  }
                  onReject={() =>
                    run('Could not reject the solution', () =>
                      api.updateDiscoveryPackageItem(token!, pkg.id, item.id, { status: 'rejected' })
                    )
                  }
                />
              ))}
            </ul>
          )}
        </div>

        {/* What do you need to know */}
        <div>
          <p className="m-0 mb-1 flex items-center gap-1.5 text-label-caps text-muted-foreground">
            <MessageCircleQuestion className="h-3.5 w-3.5" /> What else do you need to know?
          </p>
          <p className="m-0 mb-2 text-xs text-muted-foreground">
            Say it in your own words. The agent turns it into questions{' '}
            {employeeName || 'the employee'} can answer — you don&apos;t write the question text.
          </p>
          <form
            className="space-y-2"
            onSubmit={(e: FormEvent) => {
              e.preventDefault();
              if (!statement.trim()) return;
              run('Could not record what you need', async () => {
                await api.createConsultantRequirement(token!, pkg.id, statement.trim());
                setStatement('');
              });
            }}
          >
            <Textarea
              value={statement}
              onChange={(e) => setStatement(e.target.value)}
              rows={2}
              placeholder="e.g. I need to know which system is the system of record for approvals, and who signs off"
            />
            <div className="flex flex-wrap items-center gap-3">
              <Button type="submit" size="sm" disabled={busy || !statement.trim()}>
                Draft questions
              </Button>
              <span
                className={cn(
                  'text-xs tabular-nums',
                  canSend ? 'text-muted-foreground' : 'text-warning'
                )}
              >
                {canSend
                  ? `${pkg.followup_budget_remaining} more question${
                      pkg.followup_budget_remaining === 1 ? '' : 's'
                    } can be asked of this person`
                  : 'This person has been asked as many follow-ups as allowed'}
              </span>
            </div>
          </form>

          {pkg.requirements.length > 0 && (
            <ul className="m-0 mt-3 list-none space-y-2 p-0">
              {pkg.requirements.map((requirement) => (
                <RequirementCard
                  key={requirement.id}
                  requirement={requirement}
                  questions={questionsByRequirement.get(requirement.id) ?? []}
                  busy={busy}
                  onSatisfy={() =>
                    run('Could not close this', () =>
                      api.updateConsultantRequirement(token!, pkg.id, requirement.id, 'satisfied')
                    )
                  }
                  onWithdraw={() =>
                    run('Could not withdraw this', () =>
                      api.updateConsultantRequirement(token!, pkg.id, requirement.id, 'withdrawn')
                    )
                  }
                />
              ))}
            </ul>
          )}
        </div>

        {/* The agent's own drafted follow-ups */}
        {unattached.length > 0 && (
          <div>
            <p className="m-0 mb-2 text-label-caps text-muted-foreground">
              Questions the agent intends to ask ({unattached.length})
            </p>
            <ol className="m-0 list-none space-y-2 p-0">
              {unattached.map((q) => (
                <QuestionRow
                  key={q.id}
                  question={q}
                  isNext={q.id === firstPendingId}
                  canSend={canSend}
                  busy={busy}
                  onSend={() =>
                    run('Could not send the question', () =>
                      api.sendDiscoveryFollowupQuestion(token!, pkg.id, q.id)
                    )
                  }
                  onSkip={() =>
                    run('Could not skip the question', () =>
                      api.updateDiscoveryFollowupQuestion(token!, pkg.id, q.id, { status: 'skipped' })
                    )
                  }
                />
              ))}
            </ol>
          </div>
        )}
      </div>
    </Card>
  );
}
