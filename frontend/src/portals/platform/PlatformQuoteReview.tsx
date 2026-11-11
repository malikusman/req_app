import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { AlertTriangle } from 'lucide-react';
import { api, type Stage1QuoteDetail } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { formatMoney, formatPercent } from '../../lib/money';
import { Badge, Button, Card, ErrorNotice, Input, Modal, PageHeader, Select, Skeleton, Textarea } from '../../components/ui';
import { useToast } from '../../components/ui/ToastProvider';
import { QuoteDocument } from '../shared/quote/QuoteDocument';
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_VARIANTS, engagementStatusLabel } from './engagementStatus';

/** Doc 17 §9.3's structured reasons, in plain words. */
const REASON_LABELS: Record<string, string> = {
  RELATIONSHIP: 'Strategic client or relationship value',
  COMPETITIVE: 'Competitive situation',
  COMPLEXITY_UNDER: 'The estimate is too low',
  COMPLEXITY_OVER: 'The estimate is too high',
  DELIVERY_SOURCE: 'Different delivery mix than assumed',
  SCOPE_CLARIFICATION: 'Scope understood differently',
  BUNDLE: 'Shared-cost or multi-item consideration',
  OTHER: 'Other (say what)',
};

const HOURS_LABELS: Record<string, string> = {
  oversight_and_report: 'Oversight, report review and release',
  team_conversations: 'Team conversations',
  deep_dives: 'Deep dives: plan improvement and completeness',
  leadership_conversations: 'Leadership conversations',
  languages: 'Extra working languages',
  locations: 'Extra locations',
};

const COST_LABELS: Record<string, string> = {
  consultant_time: 'Consultant time',
  ai_usage: 'AI usage',
  platform_allocation: 'Platform running cost',
  licences: 'Licences',
};

const EVENT_LABELS: Record<string, string> = {
  proposed: 'Proposed by the platform',
  inputs_changed: 'Recalculated with corrected inputs',
  adjusted: 'Price adjusted',
  explained: 'Explained by P24',
  explanation_fallback: 'P24 explanation unavailable — template used',
  floor_overridden: 'Issued below the margin floor',
  issued: 'Approved and issued to the client',
  viewed: 'First opened by the client',
  pdf_generated: 'PDF made',
  accepted: 'Accepted by the client',
  declined: 'Declined by the client',
  expired: 'Expired unanswered',
  rejected: 'Sent back',
  superseded: 'Replaced by a newer version',
};

type Dialog = 'approve' | 'adjust' | 'inputs' | 'reject' | 'close' | null;

function when(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}

/**
 * The administrator's review of one Stage 1 quote (Doc 17 §9, Doc 21 §26):
 * how the fee was derived, what Mjadi expects to spend and earn on it, what
 * could make it wrong, and exactly what the client will see. Approving issues
 * it; below the margin floor that needs a structured reason, as does any
 * change to the price.
 */
export function PlatformQuoteReview() {
  const { id } = useParams();
  const token = usePlatformToken();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [data, setData] = useState<Stage1QuoteDetail | null>(null);
  const [error, setError] = useState('');
  const [dialog, setDialog] = useState<Dialog>(null);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState('');
  const [form, setForm] = useState<Record<string, string>>({});

  const load = useCallback(() => {
    if (!token || !id) return;
    api
      .platformStage1Quote(token, Number(id))
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load the quote'));
  }, [token, id]);

  useEffect(load, [load]);

  const open = (which: Dialog, initial: Record<string, string> = {}) => {
    setForm(initial);
    setActionError('');
    setDialog(which);
  };

  const run = async (action: () => Promise<Stage1QuoteDetail | unknown>, done: string) => {
    setBusy(true);
    setActionError('');
    try {
      const result = await action();
      setDialog(null);
      toast({ title: done, variant: 'success' });
      const next = result as Stage1QuoteDetail | undefined;
      if (next?.quote && next.quote.id !== Number(id)) {
        navigate(`/platform/pricing/${next.quote.id}`);
      } else if (next?.quote) {
        setData(next);
      } else {
        load();
      }
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'That didn’t work');
    } finally {
      setBusy(false);
    }
  };

  if (error) return <ErrorNotice message={error} onRetry={load} />;
  if (!data || !token) return <Skeleton className="h-96 w-full" />;

  const { quote, engagement } = data;
  const money = (amount: string) => formatMoney(amount, quote.currency);
  const latest = data.versions[0]?.id === quote.id;
  const pricing = engagement.status === 'STAGE_1_PRICING';
  const canDecide = data.can_act && pricing && quote.status === 'PROPOSED';
  const canRevise = data.can_act && pricing && latest && ['PROPOSED', 'REJECTED', 'DECLINED', 'EXPIRED'].includes(quote.status);
  const canRestart = data.can_act && pricing && latest && ['REJECTED', 'DECLINED', 'EXPIRED'].includes(quote.status);
  const explanation = quote.admin_explanation;
  const hasExplanation = Boolean(explanation?.headline);
  const reasonOptions = [{ value: '', label: 'Choose a reason' }].concat(
    data.override_reasons.map((r) => ({ value: r, label: REASON_LABELS[r] ?? r }))
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title={`${quote.company_name} — Stage 1 quote v${quote.version}`}
        description={`${engagementStatusLabel(engagement.status)}${engagement.lead_consultant ? ` · Lead: ${engagement.lead_consultant}` : ''}`}
        breadcrumbs={[
          { label: 'Pricing', href: '/platform/pricing' },
          { label: quote.company_name, href: `/platform/companies/${quote.company_id}` },
        ]}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant={QUOTE_STATUS_VARIANTS[quote.status]}>{QUOTE_STATUS_LABELS[quote.status]}</Badge>
            {canDecide ? (
              <Button onClick={() => open('approve')}>Approve and issue</Button>
            ) : null}
            {canRevise ? (
              <>
                <Button variant="secondary" onClick={() => open('adjust', { subtotal: quote.subtotal.replace(/\.0+$/, '') })}>
                  Adjust price
                </Button>
                <Button
                  variant="secondary"
                  onClick={() =>
                    open('inputs', {
                      deep_dives: String(quote.deep_dives_included),
                      locations: String(quote.inputs.locations),
                      country: quote.inputs.country ?? '',
                    })
                  }
                >
                  Change inputs
                </Button>
              </>
            ) : null}
            {canDecide ? (
              <Button variant="ghost" onClick={() => open('reject')}>
                Send back
              </Button>
            ) : null}
            {canRestart ? (
              <>
                <Button
                  variant="secondary"
                  loading={busy}
                  onClick={() => run(() => api.platformCalculateQuote(token, engagement.id), 'A fresh version is ready to review')}
                >
                  Prepare a fresh version
                </Button>
                <Button variant="ghost" onClick={() => open('close')}>
                  Close engagement
                </Button>
              </>
            ) : null}
          </div>
        }
      />

      {!data.can_act ? (
        <Notice tone="info">You can review prices; only a super admin can approve or change them.</Notice>
      ) : null}
      {data.rate_card.placeholder ? (
        <Notice tone="warning">
          Rate card v{data.rate_card.version} holds placeholder values until the rate card and Stage 1 formula are agreed
          (Decision Register K2). Check the figures before approving.
        </Notice>
      ) : null}
      {quote.below_floor ? (
        <Notice tone="error">
          This quote's margin ({formatPercent(quote.margin_percent)}) is below the {formatPercent(data.margin_floor.percent)}{' '}
          floor. It can only be issued with an override and a recorded reason.
        </Notice>
      ) : null}
      {quote.rejection_note ? (
        <Notice tone="info">
          Sent back by {quote.rejected_by} on {when(quote.rejected_at)}: {quote.rejection_note}
        </Notice>
      ) : null}
      {quote.status === 'DECLINED' ? (
        <Notice tone="error">
          The client declined on {when(quote.declined_at)}
          {quote.decline_reason ? `: ${quote.decline_reason}` : '.'} Prepare a fresh version or close the engagement.
        </Notice>
      ) : null}
      {quote.status === 'EXPIRED' ? (
        <Notice tone="info">This quote expired on {quote.valid_until} without an answer.</Notice>
      ) : null}
      {quote.status === 'ACCEPTED' ? (
        <Notice tone="success">
          Accepted by {quote.accepted_by} on {when(quote.accepted_at)}. Stage 1 has started.
        </Notice>
      ) : null}
      {!latest ? (
        <Notice tone="info">
          A newer version exists. <Link to={`/platform/pricing/${data.versions[0]?.id}`}>Open v{data.versions[0]?.version}</Link>
        </Notice>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <Card title="How the fee was derived">
            {hasExplanation ? (
              <p className="mb-4 text-sm font-medium text-text-primary">{explanation.headline}</p>
            ) : (
              <p className="mb-4 text-sm text-text-secondary">
                {quote.explanation_source === 'TEMPLATE' && quote.status === 'PROPOSED'
                  ? 'P24’s explanation isn’t available yet, or couldn’t be used; the computed derivation is below.'
                  : 'The computed derivation.'}
              </p>
            )}
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-border text-left text-xs text-text-secondary">
                  <th className="py-2 font-medium">Component</th>
                  <th className="py-2 text-right font-medium">Quantity × unit</th>
                  <th className="py-2 text-right font-medium">Amount</th>
                </tr>
              </thead>
              <tbody>
                {quote.line_items.map((line) => {
                  const why = explanation?.derivation?.find((d) => d.component === line.label)?.why ?? line.detail;
                  return (
                    <tr key={line.key} className="border-b border-border align-top">
                      <td className="py-2 pr-4">
                        <p className="m-0 font-medium">{line.label}</p>
                        {why ? <p className="m-0 text-xs text-text-secondary">{why}</p> : null}
                      </td>
                      <td className="py-2 text-right tabular-nums text-text-secondary">
                        {line.quantity} × {money(line.unit_amount)}
                      </td>
                      <td className="py-2 text-right tabular-nums">{money(line.amount)}</td>
                    </tr>
                  );
                })}
                <tr className="border-b border-border">
                  <td className="py-2">Subtotal</td>
                  <td />
                  <td className="py-2 text-right tabular-nums">{money(quote.subtotal)}</td>
                </tr>
                <tr className="border-b border-border">
                  <td className="py-2">VAT ({Number((Number(quote.tax_rate) * 100).toFixed(2))}%)</td>
                  <td />
                  <td className="py-2 text-right tabular-nums">{money(quote.tax_amount)}</td>
                </tr>
                <tr>
                  <td className="pt-2 font-semibold">Total</td>
                  <td />
                  <td className="pt-2 text-right font-semibold tabular-nums">{money(quote.total)}</td>
                </tr>
              </tbody>
            </table>
            <p className="mt-3 text-sm text-text-secondary">
              Additional participants: {money(quote.additional_participant_rate)} each.
            </p>
            {hasExplanation ? (
              <div className="mt-4 space-y-2 text-sm text-text-secondary">
                {explanation.effort_basis ? <p className="m-0">{explanation.effort_basis}</p> : null}
                {explanation.comparables_note ? <p className="m-0">{explanation.comparables_note}</p> : null}
                {explanation.recommendation_note ? (
                  <p className="m-0 font-medium text-text-primary">{explanation.recommendation_note}</p>
                ) : null}
              </div>
            ) : null}
          </Card>

          <Card title={`What could make this wrong · ${quote.estimate.confidence} confidence`}>
            <ul className="m-0 list-disc space-y-1 pl-5 text-sm text-text-secondary">
              {(hasExplanation && explanation.what_could_make_this_wrong?.length
                ? explanation.what_could_make_this_wrong
                : quote.estimate.risk_signals.map((s) => s.text)
              ).map((risk) => (
                <li key={risk}>{risk}</li>
              ))}
              {!quote.estimate.risk_signals.length && !hasExplanation ? <li>The platform flagged nothing.</li> : null}
            </ul>
          </Card>

          <Card title="What the client will see">
            <QuoteDocument
              currency={quote.currency}
              lineItems={quote.line_items}
              subtotal={quote.subtotal}
              taxRate={quote.tax_rate}
              taxAmount={quote.tax_amount}
              total={quote.total}
              additionalParticipantRate={quote.additional_participant_rate}
              scope={quote.client_scope}
            />
            <p className="mt-4 text-xs text-text-secondary">
              Scope wording: {quote.explanation_source === 'P24' ? 'written by P24 and checked' : 'the template'}.
            </p>
          </Card>
        </div>

        <div className="space-y-4">
          <Card title="Margin">
            <p className="m-0 text-3xl font-semibold tabular-nums">{formatPercent(quote.margin_percent)}</p>
            <p className="m-0 text-sm text-text-secondary">
              against fully loaded cost · floor {formatPercent(data.margin_floor.percent)} (v{data.margin_floor.version})
            </p>
            <dl className="mt-4 space-y-1 text-sm">
              {Object.entries(quote.estimate.cost)
                .filter(([k]) => k !== 'total')
                .map(([k, v]) => (
                  <Row key={k} label={COST_LABELS[k] ?? k} value={money(v)} />
                ))}
              <Row label="Fully loaded cost" value={money(quote.estimate.cost.total)} strong />
            </dl>
          </Card>

          <Card title={`Consultant hours · ${Number(quote.estimate.total_hours)}`}>
            <dl className="space-y-1 text-sm">
              {Object.entries(quote.estimate.hours).map(([k, v]) => (
                <Row key={k} label={HOURS_LABELS[k] ?? k} value={`${Number(v)} h`} />
              ))}
              <Row label="Internal cost per hour" value={money(quote.estimate.consultant_internal_cost)} />
            </dl>
          </Card>

          <Card title="Inputs">
            <dl className="space-y-1 text-sm">
              {quote.inputs.departments.map((d) => (
                <Row key={d.name} label={d.name} value={`${d.count} ${d.count === 1 ? 'person' : 'people'}`} />
              ))}
              <Row label="Named so far" value={`${quote.inputs.named_participants} of ${quote.inputs.participants}`} />
              <Row label="Other managers" value={String(quote.inputs.key_persons)} />
              <Row label="Languages" value={quote.inputs.languages.join(', ').toUpperCase()} />
              <Row label="Locations" value={`${quote.inputs.locations}${source(quote.inputs.sources.locations)}`} />
              <Row label="Country for tax" value={`${quote.inputs.country ?? 'AE (default)'}${source(quote.inputs.sources.country)}`} />
              <Row label="Deep dives" value={`${quote.deep_dives_included}${source(quote.inputs.sources.deep_dives)}`} />
            </dl>
          </Card>

          <Card title="Comparables">
            {data.comparables.length ? (
              <ul className="m-0 list-none space-y-2 p-0 text-sm">
                {data.comparables.map((c, i) => (
                  <li key={i} className="text-text-secondary">
                    {c.participants} people, {c.deep_dives} deep dives — {formatMoney(c.fee, c.currency)}
                    <br />
                    <span className="text-xs">
                      Estimated {c.estimated_hours ?? '—'} h · actual hours not recorded yet
                    </span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="m-0 text-sm text-text-secondary">No accepted Stage 1 work of a similar size yet.</p>
            )}
          </Card>

          {data.additional_participants ? (
            <Card title="Added after the price">
              <p className="m-0 text-sm text-text-secondary">
                {data.additional_participants.count} × {money(data.additional_participants.rate)} ={' '}
                {money(data.additional_participants.amount)}
              </p>
            </Card>
          ) : null}

          <Card title="Versions and history">
            <ul className="m-0 list-none space-y-1 p-0 text-sm">
              {data.versions.map((v) => (
                <li key={v.id}>
                  {v.id === quote.id ? (
                    <span className="font-medium">v{v.version}</span>
                  ) : (
                    <Link to={`/platform/pricing/${v.id}`}>v{v.version}</Link>
                  )}{' '}
                  · {formatMoney(v.total, v.currency)} · {QUOTE_STATUS_LABELS[v.status]}
                </li>
              ))}
            </ul>
            <ol className="mt-4 list-none space-y-2 border-t border-border p-0 pt-3 text-xs text-text-secondary">
              {data.events.map((e, i) => (
                <li key={i}>
                  <span className="font-medium text-text-primary">{EVENT_LABELS[e.event] ?? e.event}</span>
                  {e.by ? ` · ${e.by}` : ''} · {when(e.at)}
                  {typeof e.detail?.reason === 'string' ? <div>Reason: {REASON_LABELS[e.detail.reason] ?? e.detail.reason}</div> : null}
                  {typeof e.detail?.note === 'string' ? <div>{e.detail.note}</div> : null}
                </li>
              ))}
            </ol>
            {data.overrides.length ? (
              <ul className="mt-3 list-none space-y-1 border-t border-border p-0 pt-3 text-xs text-text-secondary">
                {data.overrides.map((o, i) => (
                  <li key={i}>
                    {o.kind === 'FLOOR_OVERRIDE' ? 'Floor override' : `Adjusted ${money(o.original_total)} → ${money(o.adjusted_total)}`}
                    {' · '}
                    {REASON_LABELS[o.structured_reason] ?? o.structured_reason}
                    {o.free_text ? ` — ${o.free_text}` : ''} · {o.actor}
                  </li>
                ))}
              </ul>
            ) : null}
          </Card>
        </div>
      </div>

      <Modal
        open={dialog === 'approve'}
        onClose={() => setDialog(null)}
        title="Approve and issue to the client"
        footer={
          <Button
            loading={busy}
            disabled={quote.below_floor && !form.reason}
            onClick={() =>
              run(
                () =>
                  api.platformApproveQuote(
                    token,
                    quote.id,
                    quote.below_floor ? { reason: form.reason, free_text: form.free_text } : undefined
                  ),
                'Issued to the client'
              )
            }
          >
            Approve and issue
          </Button>
        }
      >
        <div className="space-y-3 text-sm">
          <p className="m-0">
            {quote.company_name}’s key user will be told their proposal is ready: {money(quote.total)} including VAT, for{' '}
            {quote.participants_included} people and {quote.deep_dives_included} deep dives.
          </p>
          {quote.below_floor ? (
            <>
              <p className="m-0 text-status-error">
                The margin is below the floor. Record why it should go out anyway.
              </p>
              <Select
                label="Reason"
                options={reasonOptions}
                value={form.reason ?? ''}
                onChange={(e) => setForm({ ...form, reason: e.target.value })}
              />
              <Textarea
                label="In your words"
                value={form.free_text ?? ''}
                onChange={(e) => setForm({ ...form, free_text: e.target.value })}
              />
            </>
          ) : null}
          {actionError ? <p className="m-0 text-status-error">{actionError}</p> : null}
        </div>
      </Modal>

      <Modal
        open={dialog === 'adjust'}
        onClose={() => setDialog(null)}
        title="Adjust the price"
        footer={
          <Button
            loading={busy}
            disabled={!form.subtotal || !form.reason}
            onClick={() =>
              run(
                () =>
                  api.platformAdjustQuote(token, quote.id, {
                    subtotal: form.subtotal,
                    reason: form.reason,
                    free_text: form.free_text,
                  }),
                'A new version with the adjusted price is ready'
              )
            }
          >
            Save as a new version
          </Button>
        }
      >
        <div className="space-y-3 text-sm">
          <p className="m-0 text-text-secondary">
            The calculated lines stay; the difference shows as an adjustment. VAT and margin are worked out again.
          </p>
          <Input
            label={`Fee before VAT (${quote.currency})`}
            inputMode="decimal"
            value={form.subtotal ?? ''}
            onChange={(e) => setForm({ ...form, subtotal: e.target.value })}
          />
          <Select
            label="Reason"
            options={reasonOptions}
            value={form.reason ?? ''}
            onChange={(e) => setForm({ ...form, reason: e.target.value })}
          />
          <Textarea
            label="In your words"
            value={form.free_text ?? ''}
            onChange={(e) => setForm({ ...form, free_text: e.target.value })}
          />
          {actionError ? <p className="m-0 text-status-error">{actionError}</p> : null}
        </div>
      </Modal>

      <Modal
        open={dialog === 'inputs'}
        onClose={() => setDialog(null)}
        title="Change inputs and recalculate"
        footer={
          <Button
            loading={busy}
            onClick={() =>
              run(
                () =>
                  api.platformChangeQuoteInputs(token, quote.id, {
                    deep_dives: form.deep_dives,
                    locations: form.locations,
                    country: form.country,
                  }),
                'Recalculated as a new version'
              )
            }
          >
            Recalculate
          </Button>
        }
      >
        <div className="space-y-3 text-sm">
          <p className="m-0 text-text-secondary">
            Who takes part is the plan’s, settled with the client; change it from the engagement. These three you can
            correct here.
          </p>
          <Input
            label="Deep dives"
            inputMode="numeric"
            value={form.deep_dives ?? ''}
            onChange={(e) => setForm({ ...form, deep_dives: e.target.value })}
          />
          <Input
            label="Locations"
            inputMode="numeric"
            value={form.locations ?? ''}
            onChange={(e) => setForm({ ...form, locations: e.target.value })}
          />
          <Input
            label="Country for tax (e.g. AE, SA)"
            value={form.country ?? ''}
            onChange={(e) => setForm({ ...form, country: e.target.value })}
          />
          {actionError ? <p className="m-0 text-status-error">{actionError}</p> : null}
        </div>
      </Modal>

      <Modal
        open={dialog === 'reject'}
        onClose={() => setDialog(null)}
        title="Send back"
        footer={
          <Button
            variant="danger"
            loading={busy}
            disabled={!form.note?.trim()}
            onClick={() => run(() => api.platformRejectQuote(token, quote.id, form.note), 'Sent back to the lead consultant')}
          >
            Send back
          </Button>
        }
      >
        <div className="space-y-3 text-sm">
          <p className="m-0 text-text-secondary">
            The lead consultant is told, with your note — say what needs checking with the client.
          </p>
          <Textarea label="Note" value={form.note ?? ''} onChange={(e) => setForm({ ...form, note: e.target.value })} />
          {actionError ? <p className="m-0 text-status-error">{actionError}</p> : null}
        </div>
      </Modal>

      <Modal
        open={dialog === 'close'}
        onClose={() => setDialog(null)}
        title="Close the engagement"
        footer={
          <Button
            variant="danger"
            loading={busy}
            disabled={!form.reason?.trim()}
            onClick={() =>
              run(() => api.platformCloseEngagement(token, engagement.id, form.reason), 'Engagement closed')
            }
          >
            Close engagement
          </Button>
        }
      >
        <div className="space-y-3 text-sm">
          <p className="m-0 text-text-secondary">The Stage 1 price wasn’t agreed. Record why the engagement ends here.</p>
          <Textarea label="Reason" value={form.reason ?? ''} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
          {actionError ? <p className="m-0 text-status-error">{actionError}</p> : null}
        </div>
      </Modal>
    </div>
  );
}

function source(value: string | undefined) {
  return value === 'ADMINISTRATOR' ? ' (corrected)' : '';
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex justify-between gap-3">
      <dt className="text-text-secondary">{label}</dt>
      <dd className={`m-0 text-right tabular-nums ${strong ? 'font-semibold text-text-primary' : ''}`}>{value}</dd>
    </div>
  );
}

function Notice({ tone, children }: { tone: 'info' | 'warning' | 'error' | 'success'; children: ReactNode }) {
  const styles = {
    info: 'border-border bg-surface-muted text-text-secondary',
    warning: 'border-status-warning bg-status-warningBg text-text-primary',
    error: 'border-status-error bg-status-errorBg text-text-primary',
    success: 'border-status-success bg-status-successBg text-text-primary',
  }[tone];
  return (
    <div role="status" className={`flex items-start gap-2 rounded-card border px-4 py-3 text-sm ${styles}`}>
      {tone === 'warning' || tone === 'error' ? <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden /> : null}
      <div>{children}</div>
    </div>
  );
}
