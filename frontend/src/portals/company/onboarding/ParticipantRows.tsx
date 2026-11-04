import { useState, type FormEvent } from 'react';
import { X } from 'lucide-react';
import { api, type PlannedParticipant, type PlannedParticipantInput } from '../../../lib/api';
import { Button, Input, Select } from '../../../components/ui';

const COPY = {
  EMPLOYEE: {
    title: 'Who will take part? (optional)',
    intro: 'Name anyone you already have in mind. You can add them later too — where several people share a role, one is enough.',
    add: 'Add a person',
  },
  KEY_PERSON: {
    title: 'Who else in management should we speak with? (optional)',
    intro: 'Department heads or other managers whose view of the business we should hear.',
    add: 'Add a manager',
  },
} as const;

// Not a department name a client could choose, so it can't collide with one.
const NO_DEPARTMENT = '__none__';

/**
 * The people the key user plans to involve (Doc 07 §7, P3 and P4). Saved as they
 * are added; nobody is invited from here.
 */
export function ParticipantRows({
  token,
  type,
  participants,
  departments,
  onChange,
}: {
  token: string;
  type: PlannedParticipant['participant_type'];
  participants: PlannedParticipant[];
  /** The departments chosen to take part, offered for staff. */
  departments: string[];
  onChange: (next: PlannedParticipant[]) => void;
}) {
  const empty: PlannedParticipantInput = { participant_type: type, name: '', role_title: '', department: '', scope: '', phone_e164: '', email: '' };
  const [draft, setDraft] = useState<PlannedParticipantInput>(empty);
  const [adding, setAdding] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const copy = COPY[type];
  const rows = participants.filter((p) => p.participant_type === type);
  const set = (key: keyof PlannedParticipantInput, value: string) => setDraft((d) => ({ ...d, [key]: value }));

  const add = async (e: FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setMessage('');
    try {
      const res = await api.addPlannedParticipant(token, draft);
      onChange([...participants, res.participant]);
      setDraft(empty);
      setAdding(false);
      if (res.warnings.length) setMessage(res.warnings.join(' '));
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Could not add this person');
    } finally {
      setSaving(false);
    }
  };

  // A person planned in a department that has since been taken out of P1 keeps
  // it, so nothing is lost; the key user is asked where they now belong.
  const outsidePlan = (p: PlannedParticipant) =>
    type === 'EMPLOYEE' && Boolean(p.department) && !departments.some((d) => d.toLowerCase() === p.department!.toLowerCase());

  const move = async (id: number, department: string) => {
    setMessage('');
    try {
      const res = await api.updatePlannedParticipant(token, id, { department });
      onChange(participants.map((p) => (p.id === id ? res.participant : p)));
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Could not move this person');
    }
  };

  const remove = async (id: number) => {
    try {
      await api.removePlannedParticipant(token, id);
      onChange(participants.filter((p) => p.id !== id));
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Could not remove this person');
    }
  };

  return (
    <fieldset className="space-y-2">
      <legend className="text-sm font-medium text-foreground">{copy.title}</legend>
      <p className="m-0 text-xs text-muted-foreground">{copy.intro}</p>

      {rows.length > 0 && (
        <ul className="m-0 list-none space-y-2 p-0">
          {rows.map((p) => (
            <li key={p.id} className="space-y-2 rounded-lg border border-border px-3 py-2 text-sm">
              <div className="flex items-center justify-between gap-2">
                <span>
                  <span className="font-medium text-foreground">{p.name}</span>
                  <span className="text-muted-foreground">
                    {[p.role_title, type === 'EMPLOYEE' ? p.department : p.scope].filter(Boolean).map((v) => ` · ${v}`)}
                  </span>
                </span>
                <button
                  type="button"
                  aria-label={`Remove ${p.name}`}
                  className="text-muted-foreground hover:text-foreground"
                  onClick={() => remove(p.id)}
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
              {outsidePlan(p) && (
                <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
                  <p className="m-0 text-xs text-status-warning">
                    {p.department} is no longer one of the departments taking part.
                  </p>
                  <Select
                    label={`Move ${p.name} to`}
                    value=""
                    onChange={(e) => e.target.value && move(p.id, e.target.value === NO_DEPARTMENT ? '' : e.target.value)}
                    options={[
                      { value: '', label: 'Choose…' },
                      ...departments.map((d) => ({ value: d, label: d })),
                      { value: NO_DEPARTMENT, label: 'No department' },
                    ]}
                  />
                </div>
              )}
            </li>
          ))}
        </ul>
      )}

      {message && <p className="m-0 text-xs text-status-error">{message}</p>}

      {adding ? (
        <form onSubmit={add} className="grid gap-3 rounded-lg border border-border p-3 sm:grid-cols-2">
          <Input label="Name" value={draft.name} onChange={(e) => set('name', e.target.value)} required />
          <Input label="Role" value={draft.role_title} onChange={(e) => set('role_title', e.target.value)} />
          {type === 'EMPLOYEE' ? (
            <Select
              label="Department"
              value={draft.department}
              onChange={(e) => set('department', e.target.value)}
              options={[{ value: '', label: 'Choose…' }, ...departments.map((d) => ({ value: d, label: d }))]}
            />
          ) : (
            <Input label="Area they lead" value={draft.scope} onChange={(e) => set('scope', e.target.value)} placeholder="e.g. Sales, UAE" />
          )}
          <Input label="Phone" type="tel" value={draft.phone_e164} onChange={(e) => set('phone_e164', e.target.value)} placeholder="+971…" />
          <Input label="Email" type="email" value={draft.email} onChange={(e) => set('email', e.target.value)} />
          <div className="flex items-end justify-end gap-2 sm:col-span-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => setAdding(false)}>
              Cancel
            </Button>
            <Button type="submit" size="sm" loading={saving}>
              Add
            </Button>
          </div>
        </form>
      ) : (
        <Button type="button" variant="secondary" size="sm" onClick={() => setAdding(true)}>
          {copy.add}
        </Button>
      )}
    </fieldset>
  );
}
