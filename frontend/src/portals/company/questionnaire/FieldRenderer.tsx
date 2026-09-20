import { useState, type ReactNode } from 'react';
import { Check, Search, X } from 'lucide-react';
import { Input, Textarea } from '../../../components/ui';
import { cn } from '../../../lib/cn';
import {
  detailKey,
  fieldIsVisible,
  otherKey,
  type AnswerValue,
  type QuestionnaireAnswers,
  type QuestionnaireField,
} from '../../../lib/questionnaireOptions';

export type SetAnswer = (id: string, value: AnswerValue) => void;

/**
 * "Other" is spelled differently in different questions — Q10b offers both
 * "Other ISO certification" and "Other formal certification / standard" — so the
 * test is a prefix, not equality. Both share one sidecar; the decision, made once,
 * is not to try to distinguish which was meant.
 */
const isOtherOption = (opt: string) => opt.toLowerCase().startsWith('other');
const anyOtherSelected = (selected: string[]) => selected.some(isOtherOption);

const asArray = (v: AnswerValue): string[] => (Array.isArray(v) ? v : []);
const asString = (v: AnswerValue): string => (typeof v === 'string' ? v : '');
const asMap = (v: AnswerValue): Record<string, string | string[]> =>
  v && typeof v === 'object' && !Array.isArray(v) ? v : {};

const TIER_LABEL: Record<string, string> = {
  essential: 'Essential',
  recommended: 'Recommended',
  optional: 'Optional',
};

/** Says what a question costs you before you read it. */
function TierTag({ tier }: { tier?: string }) {
  if (!tier || !TIER_LABEL[tier]) return null;
  return (
    <span
      className={cn(
        'ml-2 align-middle text-[0.65rem] font-semibold uppercase tracking-wide',
        tier === 'essential' ? 'text-primary' : 'text-muted-foreground'
      )}
    >
      {TIER_LABEL[tier]}
    </span>
  );
}

function Legend({ field }: { field: QuestionnaireField }) {
  return (
    <>
      <legend className="text-sm font-medium text-foreground">
        {field.label}
        <TierTag tier={field.tier} />
      </legend>
      {field.helper && <p className="m-0 mt-1 text-xs text-muted-foreground">{field.helper}</p>}
    </>
  );
}

function ChoiceButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={cn(
        'min-h-11 w-full rounded-lg border px-3 py-2.5 text-left text-sm transition-colors',
        active
          ? 'border-primary bg-primary/10 text-foreground'
          : 'border-border text-muted-foreground hover:border-primary/40 hover:bg-muted/40'
      )}
    >
      {children}
    </button>
  );
}

/** The "Please specify" box that appears once an "Other" choice is made. */
function OtherInput({
  field,
  answers,
  setAnswer,
}: {
  field: QuestionnaireField;
  answers: QuestionnaireAnswers;
  setAnswer: SetAnswer;
}) {
  const key = otherKey(field.id);
  return (
    <Input
      label="Please specify"
      value={asString(answers[key])}
      maxLength={120}
      placeholder="What does “Other” mean here?"
      onChange={(e) => setAnswer(key, e.target.value)}
    />
  );
}

function SearchableSelect({
  options,
  value,
  onChange,
  placeholder,
  id,
  /** Names the control itself, so several on one page stay distinguishable. */
  name,
}: {
  options: string[];
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  id: string;
  name?: string;
}) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const filtered = query
    ? options.filter((o) => o.toLowerCase().includes(query.toLowerCase()))
    : options;

  if (value && !open) {
    return (
      <div className="flex items-center gap-2 rounded-lg border border-primary bg-primary/10 px-3 py-2.5">
        <span className="flex-1 text-sm text-foreground">{value}</span>
        <button
          type="button"
          aria-label={name ? `Clear ${name}` : `Clear ${value}`}
          className="text-muted-foreground hover:text-foreground"
          onClick={() => {
            onChange('');
            setQuery('');
            setOpen(true);
          }}
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <input
          id={id}
          type="text"
          value={query}
          onFocus={() => setOpen(true)}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
          placeholder={placeholder || 'Search…'}
          className="min-h-11 w-full rounded-lg border border-border bg-background py-2.5 pl-9 pr-3 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
        />
      </div>
      {open && (
        <div className="max-h-56 overflow-y-auto rounded-lg border border-border">
          {filtered.length === 0 ? (
            <p className="m-0 px-3 py-2.5 text-sm text-muted-foreground">
              Nothing matches “{query}”. Type it in full and pick “Other” if it is not listed.
            </p>
          ) : (
            filtered.map((opt) => (
              <button
                key={opt}
                type="button"
                onClick={() => {
                  onChange(opt);
                  setOpen(false);
                  setQuery('');
                }}
                className="block min-h-11 w-full px-3 py-2.5 text-left text-sm text-foreground hover:bg-muted/60"
              >
                {opt}
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}

/** Q08 — one numeric row per department chosen in Q07. */
function PerItemNumeric({
  field,
  answers,
  setAnswer,
}: {
  field: QuestionnaireField;
  answers: QuestionnaireAnswers;
  setAnswer: SetAnswer;
}) {
  const source = asArray(answers[field.sourceField || '']);
  const map = asMap(answers[field.id]);
  const unknown = field.unknownLabel || 'Not sure';

  // Rows are derived from the source question, so a department removed there
  // must not leave a stranded headcount behind.
  const set = (item: string, value: string) => {
    const next: Record<string, string | string[]> = {};
    source.forEach((s) => {
      const v = s === item ? value : map[s];
      if (v !== undefined && v !== '') next[s] = v;
    });
    setAnswer(field.id, Object.keys(next).length ? next : undefined);
  };

  if (source.length === 0) {
    return (
      <fieldset className="space-y-2">
        <Legend field={field} />
        <p className="m-0 rounded-lg border border-dashed border-border px-3 py-2.5 text-sm text-muted-foreground">
          Pick your departments above and they will appear here.
        </p>
      </fieldset>
    );
  }

  return (
    <fieldset className="space-y-2">
      <Legend field={field} />
      <div className="space-y-2">
        {source.map((item) => {
          const current = typeof map[item] === 'string' ? (map[item] as string) : '';
          const isUnknown = current === unknown;
          return (
            <div
              key={item}
              className="flex flex-wrap items-center gap-2 rounded-lg border border-border px-3 py-2"
            >
              <span className="min-w-0 flex-1 text-sm text-foreground">{item}</span>
              <input
                type="number"
                min={0}
                inputMode="numeric"
                aria-label={`Headcount for ${item}`}
                value={isUnknown ? '' : current}
                disabled={isUnknown}
                onChange={(e) => set(item, e.target.value)}
                className="min-h-11 w-24 rounded-lg border border-border bg-background px-3 text-sm tabular-nums text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary disabled:opacity-50"
              />
              <button
                type="button"
                aria-pressed={isUnknown}
                // Named per row: every row offers the same control, so an
                // unlabelled one tells a screen reader nothing about which
                // department it belongs to.
                aria-label={`${unknown}: ${item}`}
                onClick={() => set(item, isUnknown ? '' : unknown)}
                className={cn(
                  'min-h-11 rounded-lg border px-3 text-xs font-medium transition-colors',
                  isUnknown
                    ? 'border-primary bg-primary/10 text-foreground'
                    : 'border-border text-muted-foreground hover:border-primary/40'
                )}
              >
                {unknown}
              </button>
            </div>
          );
        })}
      </div>
    </fieldset>
  );
}

/** Q21 — a multi-select where each pick can carry a rough volume. */
function MultiSelectWithDetail({
  field,
  answers,
  setAnswer,
}: {
  field: QuestionnaireField;
  answers: QuestionnaireAnswers;
  setAnswer: SetAnswer;
}) {
  const selected = asArray(answers[field.id]);
  const dKey = detailKey(field.id);
  const details = asMap(answers[dKey]);

  const toggle = (opt: string) => {
    const next = selected.includes(opt)
      ? selected.filter((s) => s !== opt)
      : [...selected, opt];
    setAnswer(field.id, next);
    // Deselecting drops its detail, so nothing is stored for something the user
    // is no longer claiming.
    const trimmed: Record<string, string | string[]> = {};
    next.forEach((s) => {
      if (details[s]) trimmed[s] = details[s];
    });
    setAnswer(dKey, Object.keys(trimmed).length ? trimmed : undefined);
    if (!next.some(isOtherOption)) setAnswer(otherKey(field.id), undefined);
  };

  const setDetail = (opt: string, value: string) => {
    const next = { ...details };
    if (value) next[opt] = value;
    else delete next[opt];
    setAnswer(dKey, Object.keys(next).length ? next : undefined);
  };

  return (
    <fieldset className="space-y-2">
      <Legend field={field} />
      <div className="grid gap-2 sm:grid-cols-2">
        {(field.options || []).map((opt) => (
          <ChoiceButton key={opt} active={selected.includes(opt)} onClick={() => toggle(opt)}>
            {opt}
          </ChoiceButton>
        ))}
      </div>
      {selected.length > 0 && (
        <div className="space-y-2 rounded-lg border border-border bg-muted/30 p-3">
          <p className="m-0 text-xs text-muted-foreground">
            Roughly how often, for the ones you picked? Optional — a ballpark is useful, a blank is fine.
          </p>
          {selected.map((opt) => (
            <div key={opt} className="flex flex-wrap items-center gap-2">
              <span className="min-w-0 flex-1 text-sm text-foreground">{opt}</span>
              <input
                type="text"
                aria-label={`How often: ${opt}`}
                value={typeof details[opt] === 'string' ? (details[opt] as string) : ''}
                placeholder={field.detailPlaceholder || 'e.g. 500/day'}
                onChange={(e) => setDetail(opt, e.target.value)}
                className="min-h-11 w-36 rounded-lg border border-border bg-background px-3 text-sm text-foreground placeholder:text-muted-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
              />
            </div>
          ))}
        </div>
      )}
      {anyOtherSelected(selected) && (
        <OtherInput field={field} answers={answers} setAnswer={setAnswer} />
      )}
    </fieldset>
  );
}

/** Q29 — pick the parties, then how you reach each one. Cards, never a table. */
function TwoStageMatrix({
  field,
  answers,
  setAnswer,
}: {
  field: QuestionnaireField;
  answers: QuestionnaireAnswers;
  setAnswer: SetAnswer;
}) {
  const map = asMap(answers[field.id]);
  const parties = Object.keys(map);

  const toggleParty = (party: string) => {
    const next = { ...map };
    if (party in next) delete next[party];
    else next[party] = [];
    setAnswer(field.id, Object.keys(next).length ? next : undefined);
    if (!Object.keys(next).some(isOtherOption)) setAnswer(otherKey(field.id), undefined);
  };

  const toggleChannel = (party: string, channel: string) => {
    const current = asArray(map[party]);
    const next = {
      ...map,
      [party]: current.includes(channel)
        ? current.filter((c) => c !== channel)
        : [...current, channel],
    };
    setAnswer(field.id, next);
  };

  return (
    <fieldset className="space-y-3">
      <Legend field={field} />

      {/* The two stages are separate groupings, not one long list of toggles —
          naming them keeps a screen reader (and anything else walking the page)
          from reading a party and a channel as the same kind of choice. */}
      <div className="space-y-2" role="group" aria-label={field.stageOneLabel || 'Which parties?'}>
        <p className="m-0 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {field.stageOneLabel || 'Which parties?'}
        </p>
        <div className="grid gap-2 sm:grid-cols-2">
          {(field.options || []).map((opt) => (
            <ChoiceButton key={opt} active={opt in map} onClick={() => toggleParty(opt)}>
              {opt}
            </ChoiceButton>
          ))}
        </div>
      </div>

      {anyOtherSelected(parties) && (
        <OtherInput field={field} answers={answers} setAnswer={setAnswer} />
      )}

      {parties.length > 0 && (
        <div className="space-y-2" role="group" aria-label={field.stageTwoLabel || 'How do you reach each one?'}>
          <p className="m-0 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {field.stageTwoLabel || 'How do you reach each one?'}
          </p>
          {/* One card per party. A grid of checkboxes would be a table, and a
              table at 390px is unreadable. */}
          <div className="space-y-2">
            {parties.map((party) => (
              <div key={party} className="rounded-lg border border-border p-3">
                <p className="m-0 mb-2 text-sm font-medium text-foreground">{party}</p>
                <div className="flex flex-wrap gap-2">
                  {(field.channelOptions || []).map((ch) => {
                    const on = asArray(map[party]).includes(ch);
                    return (
                      <button
                        key={ch}
                        type="button"
                        aria-pressed={on}
                        onClick={() => toggleChannel(party, ch)}
                        className={cn(
                          'min-h-9 rounded-full border px-3 py-1.5 text-xs transition-colors',
                          on
                            ? 'border-primary bg-primary/10 text-foreground'
                            : 'border-border text-muted-foreground hover:border-primary/40'
                        )}
                      >
                        {on && <Check className="mr-1 inline h-3 w-3" />}
                        {ch}
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </fieldset>
  );
}

/** Q33 — three ranked answers, asked as three inputs rather than one box. */
function ParallelText({
  field,
  answers,
  setAnswer,
}: {
  field: QuestionnaireField;
  answers: QuestionnaireAnswers;
  setAnswer: SetAnswer;
}) {
  const labels = field.subLabels || [];
  const current = asArray(answers[field.id]);

  const set = (index: number, value: string) => {
    const next = labels.map((_, i) => (i === index ? value : current[i] || ''));
    setAnswer(field.id, next.some((v) => v.trim()) ? next : undefined);
  };

  return (
    <fieldset className="space-y-2">
      <Legend field={field} />
      <div className="space-y-2">
        {labels.map((label, i) => (
          <Input
            key={label}
            label={label}
            value={current[i] || ''}
            onChange={(e) => set(i, e.target.value)}
          />
        ))}
      </div>
    </fieldset>
  );
}

/** Q22 — one searchable row per system category. */
function CategoryMatrix({
  field,
  answers,
  setAnswer,
}: {
  field: QuestionnaireField;
  answers: QuestionnaireAnswers;
  setAnswer: SetAnswer;
}) {
  const map = asMap(answers[field.id]);

  const set = (categoryId: string, value: string) => {
    const next = { ...map };
    if (value) next[categoryId] = value;
    else delete next[categoryId];
    setAnswer(field.id, Object.keys(next).length ? next : undefined);
  };

  return (
    <fieldset className="space-y-2">
      <Legend field={field} />
      <div className="space-y-3">
        {(field.categories || []).map((cat) => (
          <div key={cat.id} className="rounded-lg border border-border p-3">
            <label
              htmlFor={`${field.id}-${cat.id}`}
              className="mb-2 block text-sm font-medium text-foreground"
            >
              {cat.label}
            </label>
            <SearchableSelect
              id={`${field.id}-${cat.id}`}
              name={cat.label}
              options={cat.options}
              value={typeof map[cat.id] === 'string' ? (map[cat.id] as string) : ''}
              placeholder="Search, or type your own…"
              onChange={(v) => set(cat.id, v)}
            />
          </div>
        ))}
      </div>
    </fieldset>
  );
}

export function FieldRenderer({
  field,
  answers,
  setAnswer,
}: {
  field: QuestionnaireField;
  answers: QuestionnaireAnswers;
  setAnswer: SetAnswer;
}) {
  if (!fieldIsVisible(field, answers)) return null;
  const raw = answers[field.id];

  switch (field.type) {
    case 'static':
      return (
        <p className="m-0 rounded-lg border border-border bg-muted/30 px-3 py-2.5 text-sm text-muted-foreground">
          {field.label}
        </p>
      );

    case 'text':
      return (
        <div className="space-y-1">
          <Input
            label={field.label}
            value={asString(raw)}
            placeholder={field.placeholder}
            onChange={(e) => setAnswer(field.id, e.target.value)}
          />
          {field.helper && <p className="m-0 text-xs text-muted-foreground">{field.helper}</p>}
        </div>
      );

    case 'textarea':
      return (
        <div className="space-y-1">
          <Textarea
            label={field.label}
            rows={4}
            value={asString(raw)}
            placeholder={field.placeholder}
            onChange={(e) => setAnswer(field.id, e.target.value)}
          />
          {field.helper && <p className="m-0 text-xs text-muted-foreground">{field.helper}</p>}
        </div>
      );

    case 'searchable_select':
      return (
        <fieldset className="space-y-2">
          <Legend field={field} />
          <SearchableSelect
            id={field.id}
            options={field.options || []}
            value={asString(raw)}
            onChange={(v) => setAnswer(field.id, v)}
          />
          {isOtherOption(asString(raw)) && (
            <OtherInput field={field} answers={answers} setAnswer={setAnswer} />
          )}
        </fieldset>
      );

    case 'single_select': {
      const value = asString(raw);
      return (
        <fieldset className="space-y-2">
          <Legend field={field} />
          <div className="grid gap-2 sm:grid-cols-2">
            {(field.options || []).map((opt) => (
              <ChoiceButton
                key={opt}
                active={value === opt}
                onClick={() => setAnswer(field.id, value === opt ? undefined : opt)}
              >
                {opt}
              </ChoiceButton>
            ))}
          </div>
          {field.withOther && isOtherOption(value) && (
            <OtherInput field={field} answers={answers} setAnswer={setAnswer} />
          )}
        </fieldset>
      );
    }

    case 'per_item_numeric':
      return <PerItemNumeric field={field} answers={answers} setAnswer={setAnswer} />;
    case 'multi_select_with_detail':
      return <MultiSelectWithDetail field={field} answers={answers} setAnswer={setAnswer} />;
    case 'two_stage_matrix':
      return <TwoStageMatrix field={field} answers={answers} setAnswer={setAnswer} />;
    case 'parallel_text':
      return <ParallelText field={field} answers={answers} setAnswer={setAnswer} />;
    case 'category_matrix':
      return <CategoryMatrix field={field} answers={answers} setAnswer={setAnswer} />;

    default: {
      // multi_select, including the grouped variant
      const selected = asArray(raw);
      const toggle = (opt: string) => {
        const next = selected.includes(opt)
          ? selected.filter((s) => s !== opt)
          : field.maxSelections && selected.length >= field.maxSelections
            ? selected
            : [...selected, opt];
        setAnswer(field.id, next);
        if (!next.some(isOtherOption)) setAnswer(otherKey(field.id), undefined);
      };
      const groups = field.groups?.length
        ? field.groups
        : [{ label: '', options: field.options || [] }];

      return (
        <fieldset className="space-y-2">
          <Legend field={field} />
          <div className="space-y-3">
            {groups.map((group, gi) => (
              <div key={group.label || gi} className="space-y-2">
                {group.label && (
                  <p className="m-0 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {group.label}
                  </p>
                )}
                <div className="grid gap-2 sm:grid-cols-2">
                  {group.options.map((opt) => (
                    <ChoiceButton
                      key={opt}
                      active={selected.includes(opt)}
                      onClick={() => toggle(opt)}
                    >
                      {opt}
                    </ChoiceButton>
                  ))}
                </div>
              </div>
            ))}
          </div>
          {field.withOther && anyOtherSelected(selected) && (
            <OtherInput field={field} answers={answers} setAnswer={setAnswer} />
          )}
        </fieldset>
      );
    }
  }
}
