import { useState } from 'react';
import { Check, Pencil, X } from 'lucide-react';
import { api, type PrefillProposal, type QuestionnaireAnswerMap } from '../../../lib/api';
import { Button, Card } from '../../../components/ui';

const FIELD_LABELS: Record<string, string> = {
  industry: 'Industry',
  products_services: 'Products and services',
  locations: 'Locations',
  business_model: 'How you operate',
  customer_channels: 'How customers reach you',
  departments: 'Departments',
  core_systems: 'Systems',
  ai_tools: 'AI tools',
};

const STATUS_LABELS: Partial<Record<PrefillProposal['status'], string>> = {
  CONFIRMED: 'Confirmed',
  CORRECTED: 'Edited by you',
  REJECTED: 'Not used',
};

/** "home page", or the page's path — the link the excerpt came from. */
function pageLabel(url: string) {
  try {
    const path = decodeURI(new URL(url).pathname);
    return path === '/' || path === '' ? 'home page' : path;
  } catch {
    return url;
  }
}

/**
 * What we read on the client's website, for them to confirm, edit or set aside
 * (Doc 07 §5). Each proposal is marked as coming from the website and shows the
 * words it came from; nothing is used until they confirm it.
 */
export function PrefillCards({
  token,
  proposals,
  reading,
  entityNote,
  onAnswered,
}: {
  token: string;
  proposals: PrefillProposal[];
  /** Still reading the website: show a quiet line instead. */
  reading: boolean;
  entityNote: string | null;
  /** A proposal was answered; `answers` are the form answers it brings in, if any. */
  onAnswered: (proposal: PrefillProposal, answers: QuestionnaireAnswerMap | undefined, action: 'confirm' | 'correct' | 'reject') => void;
}) {
  const [busy, setBusy] = useState<number | null>(null);
  const [error, setError] = useState('');

  if (reading) {
    return <p className="m-0 text-sm text-muted-foreground">Reading your website… anything we find will appear here to confirm.</p>;
  }
  if (proposals.length === 0 && !entityNote) return null;

  const answer = async (proposal: PrefillProposal, action: 'confirm' | 'correct' | 'reject') => {
    setBusy(proposal.id);
    setError('');
    try {
      const res = await api.answerPrefillProposal(token, proposal.id, action);
      onAnswered(res.candidate, res.answers, action);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save your answer');
    } finally {
      setBusy(null);
    }
  };

  const open = proposals.filter((p) => p.status === 'PROPOSED');

  return (
    <Card className="space-y-4 p-4 sm:p-6">
      <div>
        <h2 className="m-0 text-lg font-medium text-foreground">From your website</h2>
        <p className="m-0 mt-1 text-sm text-muted-foreground">
          We read your website so you don&apos;t have to type this. Confirm what&apos;s right, edit what isn&apos;t —
          nothing here is used until you do.
        </p>
      </div>

      {entityNote && (
        <p className="m-0 rounded-lg border border-border bg-muted/40 px-3 py-2 text-sm text-foreground">
          Your website describes a group of companies. Below, under &ldquo;In a few words, what exactly do you
          do?&rdquo;, tell us which company or division this engagement is for.
        </p>
      )}

      {error && <p className="m-0 text-sm text-status-error">{error}</p>}

      <ul className="m-0 list-none space-y-3 p-0">
        {proposals.map((p) => (
          <li key={p.id} className="space-y-2 rounded-lg border border-border px-3 py-3">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <p className="m-0 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                {FIELD_LABELS[p.target_field] ?? p.target_field}
                <span className="ml-2 normal-case tracking-normal">· from your website</span>
              </p>
              {STATUS_LABELS[p.status] && <span className="text-xs text-muted-foreground">{STATUS_LABELS[p.status]}</span>}
            </div>
            <p className="m-0 text-sm text-foreground">
              {p.conflicts ? <>Your website says: {p.display_text}</> : p.display_text}
            </p>
            <p className="m-0 text-xs text-muted-foreground">
              &ldquo;{p.evidence_excerpt}&rdquo; —{' '}
              <a href={p.source_url} target="_blank" rel="noreferrer" className="underline">
                {pageLabel(p.source_url)}
              </a>
            </p>
            {p.status === 'PROPOSED' && (
              <div className="flex flex-wrap gap-2">
                <Button size="sm" loading={busy === p.id} onClick={() => answer(p, 'confirm')}>
                  <Check className="mr-1 h-4 w-4" />
                  {p.conflicts ? 'Use this instead' : 'Confirm'}
                </Button>
                <Button size="sm" variant="secondary" disabled={busy === p.id} onClick={() => answer(p, 'correct')}>
                  <Pencil className="mr-1 h-4 w-4" />
                  Edit
                </Button>
                <Button size="sm" variant="secondary" disabled={busy === p.id} onClick={() => answer(p, 'reject')}>
                  <X className="mr-1 h-4 w-4" />
                  Not right
                </Button>
              </div>
            )}
          </li>
        ))}
      </ul>
      {open.length === 0 && proposals.length > 0 && (
        <p className="m-0 text-xs text-muted-foreground">All answered — thank you.</p>
      )}
    </Card>
  );
}
