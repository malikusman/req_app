import { useCallback, useEffect, useState } from 'react';
import { api, type RateCardPayload, type Stage1Rates } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { formatMoney } from '../../lib/money';
import { Badge, Button, Card, ErrorNotice, Input, PageHeader, Skeleton, Textarea } from '../../components/ui';
import { useToast } from '../../components/ui/ToastProvider';

/** One editable value of the Stage 1 formula: where it lives, how it reads, what unit it is in. */
interface Field {
  path: string;
  label: string;
  unit: 'money' | 'hours' | 'count' | 'days';
  hint?: string;
}

const GROUPS: { title: string; note: string; fields: Field[] }[] = [
  {
    title: 'Fees',
    note: 'What the client is charged (Doc 17 §2.3).',
    fields: [
      { path: 'base_fee', label: 'Base engagement', unit: 'money' },
      { path: 'per_participant_fee', label: 'Per participant', unit: 'money' },
      { path: 'per_deep_dive_fee', label: 'Per deep dive', unit: 'money' },
      { path: 'additional_participant_rate', label: 'Each person added after the price', unit: 'money' },
    ],
  },
  {
    title: 'Complexity',
    note: 'Added for each language and location beyond the first, and each department beyond the threshold.',
    fields: [
      { path: 'complexity.per_extra_language', label: 'Per extra language', unit: 'money' },
      { path: 'complexity.per_extra_location', label: 'Per extra location', unit: 'money' },
      { path: 'complexity.departments_threshold', label: 'Departments before a charge', unit: 'count' },
      { path: 'complexity.per_department_over_threshold', label: 'Per department over that', unit: 'money' },
    ],
  },
  {
    title: 'Deep dives',
    note: 'The default is the participant count, kept within this range.',
    fields: [
      { path: 'deep_dives.min', label: 'Fewest', unit: 'count' },
      { path: 'deep_dives.max', label: 'Most', unit: 'count' },
    ],
  },
  {
    title: 'Consultant hours',
    note: 'What the fee has to sustain; never shown to the client.',
    fields: [
      { path: 'hours.base', label: 'Oversight, report review and release', unit: 'hours' },
      { path: 'hours.per_participant', label: 'Per participant', unit: 'hours' },
      { path: 'hours.per_deep_dive', label: 'Per deep dive', unit: 'hours' },
      { path: 'hours.per_key_person', label: 'Per other manager', unit: 'hours' },
      { path: 'hours.per_extra_language', label: 'Per extra language', unit: 'hours' },
      { path: 'hours.per_extra_location', label: 'Per extra location', unit: 'hours' },
    ],
  },
  {
    title: 'Other costs',
    note: 'With consultant time, the fully loaded cost the margin is measured against (Doc 17 §8.2).',
    fields: [
      { path: 'ai_cost.per_participant', label: 'AI usage per participant', unit: 'money' },
      { path: 'ai_cost.per_deep_dive', label: 'AI usage per deep dive', unit: 'money' },
      { path: 'ai_cost.per_key_person', label: 'AI usage per manager', unit: 'money' },
      { path: 'platform_allocation', label: 'Platform running cost per engagement', unit: 'money' },
      { path: 'licences', label: 'Licences per engagement', unit: 'money' },
    ],
  },
];

type TaxRow = { country: string; percent: string };

interface FormState {
  values: Record<string, string>;
  internalCost: string;
  chargeRate: string;
  validityDays: string;
  taxes: TaxRow[];
  paymentTerms: string;
  termsReference: string;
  placeholder: boolean;
  reason: string;
}

function read(stage1: Stage1Rates, path: string): unknown {
  return path.split('.').reduce<unknown>((value, key) => (value as Record<string, unknown> | undefined)?.[key], stage1);
}

function write(target: Record<string, unknown>, path: string, value: string) {
  const keys = path.split('.');
  let node = target;
  keys.slice(0, -1).forEach((k) => {
    node[k] = (node[k] as Record<string, unknown>) ?? {};
    node = node[k] as Record<string, unknown>;
  });
  node[keys[keys.length - 1]] = value;
}

function toForm(data: RateCardPayload): FormState {
  const card = data.rate_card!;
  const values: Record<string, string> = {};
  GROUPS.flatMap((g) => g.fields).forEach((f) => {
    values[f.path] = String(read(card.stage1, f.path) ?? '');
  });
  return {
    values,
    internalCost: String(card.consultant_internal_cost ?? ''),
    chargeRate: String(card.consultant_charge_rate ?? ''),
    validityDays: String(card.stage1.validity_days ?? ''),
    taxes: Object.entries(card.stage1.tax_rates ?? {}).map(([country, rate]) => ({
      country,
      percent: String(Number((rate * 100).toFixed(4))),
    })),
    paymentTerms: card.stage1.payment_terms_text ?? '',
    termsReference: card.stage1.terms_reference_text ?? '',
    placeholder: false,
    reason: '',
  };
}

function shown(value: unknown, unit: Field['unit'], currency: string): string {
  if (value == null || value === '') return '—';
  if (unit === 'money') return formatMoney(value as number, currency);
  if (unit === 'hours') return `${value} h`;
  if (unit === 'days') return `${value} days`;
  return String(value);
}

function day(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

/**
 * The Stage 1 rate card and the margin floor (Doc 17 §7–8, Doc 21 §27): the
 * values in effect, every earlier version with who changed it and why, and —
 * for a super admin — a new version of either. Neither is ever edited; quotes
 * keep the version they were made with.
 */
export function PlatformRateCard() {
  const token = usePlatformToken();
  const { toast } = useToast();
  const [data, setData] = useState<RateCardPayload | null>(null);
  const [error, setError] = useState('');
  const [form, setForm] = useState<FormState | null>(null);
  const [floor, setFloor] = useState({ percent: '', reason: '' });
  const [floorOpen, setFloorOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState('');

  const load = useCallback(() => {
    if (!token) return;
    api
      .platformRateCard(token)
      .then(setData)
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load the rate card'));
  }, [token]);

  useEffect(load, [load]);

  if (error) return <ErrorNotice message={error} onRetry={load} />;
  if (!data || !token) return <Skeleton className="h-96 w-full" />;

  const card = data.rate_card;
  const currency = card?.currency ?? 'AED';

  const saveRateCard = async () => {
    if (!form) return;
    setBusy(true);
    setActionError('');
    const stage1: Record<string, unknown> = {
      validity_days: form.validityDays,
      payment_terms_text: form.paymentTerms,
      terms_reference_text: form.termsReference,
      tax_rates: Object.fromEntries(
        form.taxes
          .filter((t) => t.country.trim() && t.percent.trim())
          .map((t) => [t.country.trim().toUpperCase(), Number(t.percent) / 100])
      ),
    };
    Object.entries(form.values).forEach(([path, value]) => write(stage1, path, value));
    try {
      const next = await api.platformNewRateCard(token, {
        stage1,
        consultant_internal_cost: form.internalCost,
        consultant_charge_rate: form.chargeRate,
        currency,
        placeholder: form.placeholder,
        reason: form.reason,
      });
      setData(next);
      setForm(null);
      toast({ title: `Rate card v${next.rate_card?.version} is now in effect`, variant: 'success' });
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'That didn’t work');
    } finally {
      setBusy(false);
    }
  };

  const saveFloor = async () => {
    setBusy(true);
    setActionError('');
    try {
      const next = await api.platformNewMarginFloor(token, floor.percent, floor.reason);
      setData(next);
      setFloorOpen(false);
      setFloor({ percent: '', reason: '' });
      toast({ title: `The margin floor is now ${next.margin_floor?.percent}%`, variant: 'success' });
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'That didn’t work');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Rates and margin floor"
        description="What Stage 1 is priced from. A change is a new version, in effect from now, with who made it and why; quotes keep the version they were made with."
        breadcrumbs={[{ label: 'Pricing', href: '/platform/pricing' }, { label: 'Rates and margin floor' }]}
      />

      {card?.placeholder ? (
        <p className="m-0 rounded-card border border-status-warning bg-status-warningBg px-4 py-3 text-sm">
          Rate card v{card.version} holds placeholder values until the rate card and Stage 1 formula are agreed (Decision
          Register K2).
        </p>
      ) : null}
      {data.waiting_on_older_rates > 0 ? (
        <p className="m-0 rounded-card border border-border bg-surface-muted px-4 py-3 text-sm text-text-secondary">
          {data.waiting_on_older_rates} quote{data.waiting_on_older_rates === 1 ? ' is' : 's are'} waiting for approval on
          an earlier rate card. Each can be recalculated from its page.
        </p>
      ) : null}
      {actionError ? <p className="m-0 text-sm text-status-error">{actionError}</p> : null}

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          {card && !form ? (
            <Card
              title={`Stage 1 rate card · v${card.version}`}
              action={
                data.can_act ? (
                  <Button size="sm" onClick={() => setForm(toForm(data))}>
                    Make a new version
                  </Button>
                ) : undefined
              }
            >
              <div className="space-y-5">
                <p className="m-0 text-xs text-text-secondary">
                  In effect from {day(card.effective_from)}
                  {card.changed_by ? ` · set by ${card.changed_by}` : ''} · {card.reason}
                </p>
                {GROUPS.map((group) => (
                  <section key={group.title}>
                    <h3 className="mb-1 text-sm font-semibold text-text-primary">{group.title}</h3>
                    <dl className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
                      {group.fields.map((f) => (
                        <div key={f.path} className="flex justify-between gap-3">
                          <dt className="text-text-secondary">{f.label}</dt>
                          <dd className="m-0 whitespace-nowrap tabular-nums">{shown(read(card.stage1, f.path), f.unit, currency)}</dd>
                        </div>
                      ))}
                    </dl>
                  </section>
                ))}
                <section>
                  <h3 className="mb-1 text-sm font-semibold text-text-primary">Consultant rates</h3>
                  <dl className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
                    <div className="flex justify-between gap-3">
                      <dt className="text-text-secondary">Internal cost per hour</dt>
                      <dd className="m-0 whitespace-nowrap tabular-nums">{shown(card.consultant_internal_cost, 'money', currency)}</dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-text-secondary">Charge rate per hour</dt>
                      <dd className="m-0 whitespace-nowrap tabular-nums">{shown(card.consultant_charge_rate, 'money', currency)}</dd>
                    </div>
                  </dl>
                </section>
                <section>
                  <h3 className="mb-1 text-sm font-semibold text-text-primary">Quote terms</h3>
                  <dl className="space-y-1 text-sm">
                    <div className="flex justify-between gap-3">
                      <dt className="text-text-secondary">Validity</dt>
                      <dd className="m-0">{shown(card.stage1.validity_days, 'days', currency)}</dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-text-secondary">VAT</dt>
                      <dd className="m-0">
                        {Object.entries(card.stage1.tax_rates)
                          .map(([c, r]) => `${c} ${Number((r * 100).toFixed(2))}%`)
                          .join(' · ')}
                      </dd>
                    </div>
                  </dl>
                  <p className="mb-0 mt-2 text-xs text-text-secondary">{card.stage1.payment_terms_text}</p>
                  <p className="m-0 text-xs text-text-secondary">{card.stage1.terms_reference_text}</p>
                </section>
              </div>
            </Card>
          ) : null}

          {form ? (
            <Card title={`New rate card · v${(card?.version ?? 0) + 1}`}>
              <div className="space-y-5">
                {GROUPS.map((group) => (
                  <section key={group.title}>
                    <h3 className="m-0 text-sm font-semibold text-text-primary">{group.title}</h3>
                    <p className="mb-2 mt-0 text-xs text-text-secondary">{group.note}</p>
                    <div className="grid gap-3 sm:grid-cols-2">
                      {group.fields.map((f) => (
                        <Input
                          key={f.path}
                          label={`${f.label}${f.unit === 'money' ? ` (${currency})` : f.unit === 'hours' ? ' (hours)' : ''}`}
                          inputMode="decimal"
                          value={form.values[f.path] ?? ''}
                          onChange={(e) => setForm({ ...form, values: { ...form.values, [f.path]: e.target.value } })}
                        />
                      ))}
                    </div>
                  </section>
                ))}
                <section>
                  <h3 className="m-0 text-sm font-semibold text-text-primary">Consultant rates</h3>
                  <p className="mb-2 mt-0 text-xs text-text-secondary">Mjadi team; the other skills and sources are kept as they are.</p>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <Input
                      label={`Internal cost per hour (${currency})`}
                      inputMode="decimal"
                      value={form.internalCost}
                      onChange={(e) => setForm({ ...form, internalCost: e.target.value })}
                    />
                    <Input
                      label={`Charge rate per hour (${currency})`}
                      inputMode="decimal"
                      value={form.chargeRate}
                      onChange={(e) => setForm({ ...form, chargeRate: e.target.value })}
                    />
                  </div>
                </section>
                <section className="space-y-3">
                  <h3 className="m-0 text-sm font-semibold text-text-primary">Quote terms</h3>
                  <Input
                    label="Validity (days)"
                    inputMode="numeric"
                    value={form.validityDays}
                    onChange={(e) => setForm({ ...form, validityDays: e.target.value })}
                  />
                  <div className="space-y-2">
                    <p className="m-0 text-sm font-medium text-text-primary">VAT by country</p>
                    {form.taxes.map((row, i) => (
                      <div key={i} className="flex items-end gap-2">
                        <Input
                          label="Country (code)"
                          value={row.country}
                          onChange={(e) =>
                            setForm({ ...form, taxes: form.taxes.map((t, j) => (j === i ? { ...t, country: e.target.value } : t)) })
                          }
                        />
                        <Input
                          label="Rate (%)"
                          inputMode="decimal"
                          value={row.percent}
                          onChange={(e) =>
                            setForm({ ...form, taxes: form.taxes.map((t, j) => (j === i ? { ...t, percent: e.target.value } : t)) })
                          }
                        />
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setForm({ ...form, taxes: form.taxes.filter((_, j) => j !== i) })}
                        >
                          Remove
                        </Button>
                      </div>
                    ))}
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => setForm({ ...form, taxes: [...form.taxes, { country: '', percent: '' }] })}
                    >
                      Add a country
                    </Button>
                  </div>
                  <Textarea
                    label="Payment terms, as the quote states them"
                    value={form.paymentTerms}
                    onChange={(e) => setForm({ ...form, paymentTerms: e.target.value })}
                  />
                  <Textarea
                    label="Engagement terms reference"
                    value={form.termsReference}
                    onChange={(e) => setForm({ ...form, termsReference: e.target.value })}
                  />
                </section>
                <section className="space-y-3 border-t border-border pt-4">
                  <label className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={form.placeholder}
                      onChange={(e) => setForm({ ...form, placeholder: e.target.checked })}
                    />
                    These are still placeholder values
                  </label>
                  <Textarea
                    label="Why the rates are changing"
                    value={form.reason}
                    onChange={(e) => setForm({ ...form, reason: e.target.value })}
                  />
                  <div className="flex flex-wrap gap-2">
                    <Button loading={busy} disabled={!form.reason.trim()} onClick={saveRateCard}>
                      Put v{(card?.version ?? 0) + 1} into effect
                    </Button>
                    <Button variant="ghost" onClick={() => setForm(null)}>
                      Cancel
                    </Button>
                  </div>
                </section>
              </div>
            </Card>
          ) : null}
        </div>

        <div className="space-y-4">
          <Card
            title="Margin floor"
            action={
              data.can_act && !floorOpen ? (
                <Button variant="secondary" size="sm" onClick={() => setFloorOpen(true)}>
                  Change
                </Button>
              ) : undefined
            }
          >
            <p className="m-0 text-3xl font-semibold tabular-nums">{data.margin_floor?.percent ?? '—'}%</p>
            <p className="m-0 text-sm text-text-secondary">
              Minimum gross margin on fully loaded cost (Decision Register B12). Below it, a quote is issued only with an
              override and a recorded reason.
            </p>
            {floorOpen ? (
              <div className="mt-4 space-y-3">
                <Input
                  label="New floor (%)"
                  inputMode="decimal"
                  value={floor.percent}
                  onChange={(e) => setFloor({ ...floor, percent: e.target.value })}
                />
                <Textarea
                  label="Why the floor is changing"
                  value={floor.reason}
                  onChange={(e) => setFloor({ ...floor, reason: e.target.value })}
                />
                <div className="flex gap-2">
                  <Button loading={busy} disabled={!floor.percent || !floor.reason.trim()} onClick={saveFloor}>
                    Put into effect
                  </Button>
                  <Button variant="ghost" onClick={() => setFloorOpen(false)}>
                    Cancel
                  </Button>
                </div>
              </div>
            ) : null}
            <ol className="mt-4 list-none space-y-2 border-t border-border p-0 pt-3 text-xs text-text-secondary">
              {data.margin_floors.map((f) => (
                <li key={f.version}>
                  <span className="font-medium text-text-primary">
                    v{f.version} · {f.percent}%
                  </span>{' '}
                  · {day(f.effective_from)}
                  {f.changed_by ? ` · ${f.changed_by}` : ''}
                  <div>{f.reason}</div>
                </li>
              ))}
            </ol>
          </Card>

          <Card title="Rate card history">
            <ol className="m-0 list-none space-y-2 p-0 text-xs text-text-secondary">
              {data.rate_cards.map((r) => (
                <li key={r.version}>
                  <span className="font-medium text-text-primary">v{r.version}</span>
                  {r.version === card?.version ? (
                    <>
                      {' '}
                      <Badge variant="success">In effect</Badge>
                    </>
                  ) : null}
                  {r.placeholder ? ' · placeholder' : ''} · {day(r.effective_from)}
                  {r.changed_by ? ` · ${r.changed_by}` : ''} · {r.quotes} quote{r.quotes === 1 ? '' : 's'}
                  <div>{r.reason}</div>
                </li>
              ))}
            </ol>
          </Card>
        </div>
      </div>
    </div>
  );
}
