import { useState } from 'react';
import { Plus, Trash2, UserPlus } from 'lucide-react';
import { Button, Card, Input, Select } from '../../../components/ui';
import type { LeadershipPersonInput, LeadershipScope } from '../../../lib/api';

type Row = { name: string; count: string };

/**
 * The key user's scope card (Doc 08 §13): which departments take part, how many
 * people from each — every "Not sure" becomes a number here before Stage 1 is
 * priced — and the people they mentioned in the conversation.
 */
export function ScopeCard({
  scope,
  warnings,
  onSave,
  onConfirmPerson,
  onDismissPerson,
}: {
  scope: LeadershipScope;
  warnings: string[];
  onSave: (rows: { name: string; count: number | string }[]) => Promise<void>;
  onConfirmPerson: (index: number, person: LeadershipPersonInput) => Promise<void>;
  onDismissPerson: (index: number) => Promise<void>;
}) {
  const [rows, setRows] = useState<Row[]>(
    scope.departments.map((d) => ({ name: d.name, count: d.count === 'UNKNOWN' ? '' : String(d.count) }))
  );
  const [saving, setSaving] = useState(false);
  const [adding, setAdding] = useState<number | null>(null);
  const [person, setPerson] = useState<LeadershipPersonInput>({ participant_type: 'EMPLOYEE', name: '' });

  const unused = scope.suggested_departments.filter(
    (name) => !rows.some((r) => r.name.toLowerCase() === name.toLowerCase())
  );
  const missing = rows.filter((r) => !/^\d+$/.test(r.count.trim())).length;

  const save = async () => {
    setSaving(true);
    try {
      await onSave(rows.filter((r) => r.name.trim()).map((r) => ({ name: r.name.trim(), count: r.count.trim() || 'UNKNOWN' })));
    } finally {
      setSaving(false);
    }
  };

  const startAdding = (index: number) => {
    const mentioned = scope.people_mentioned.find((p) => p.index === index);
    setAdding(index);
    setPerson({
      participant_type: 'EMPLOYEE',
      name: mentioned?.name ?? '',
      role_title: mentioned?.role ?? '',
      department: mentioned?.department ?? '',
    });
  };

  return (
    <Card title="Who takes part">
      <div className="space-y-5">
        <div className="space-y-2">
          <p className="m-0 text-sm text-muted-foreground">
            How many people from each department should we speak with? A rough number is fine — it sets the scope of
            the first stage.
          </p>
          {rows.map((row, i) => (
            <div key={`${row.name}-${i}`} className="flex items-end gap-2">
              <div className="min-w-0 flex-1">
                <Input
                  aria-label="Department"
                  value={row.name}
                  disabled={!scope.editable}
                  onChange={(e) => setRows((prev) => prev.map((r, j) => (j === i ? { ...r, name: e.target.value } : r)))}
                />
              </div>
              <div className="w-24">
                <Input
                  aria-label={`People from ${row.name || 'this department'}`}
                  inputMode="numeric"
                  placeholder="How many?"
                  value={row.count}
                  disabled={!scope.editable}
                  onChange={(e) => setRows((prev) => prev.map((r, j) => (j === i ? { ...r, count: e.target.value } : r)))}
                />
              </div>
              {scope.editable && (
                <Button
                  variant="ghost"
                  aria-label={`Remove ${row.name}`}
                  icon={<Trash2 className="h-4 w-4" />}
                  onClick={() => setRows((prev) => prev.filter((_, j) => j !== i))}
                />
              )}
            </div>
          ))}
          {scope.editable && (
            <div className="flex flex-wrap gap-2">
              {unused.map((name) => (
                <Button key={name} size="sm" variant="secondary" icon={<Plus className="h-3.5 w-3.5" />}
                  onClick={() => setRows((prev) => [...prev, { name, count: '' }])}>
                  {name}
                </Button>
              ))}
              <Button size="sm" variant="ghost" icon={<Plus className="h-3.5 w-3.5" />}
                onClick={() => setRows((prev) => [...prev, { name: '', count: '' }])}>
                Another department
              </Button>
            </div>
          )}
          {warnings.map((w) => (
            <p key={w} className="m-0 rounded-md bg-status-warningBg px-3 py-2 text-sm text-foreground">{w}</p>
          ))}
          {scope.editable ? (
            <div className="flex items-center justify-between gap-3">
              <span className="text-xs text-muted-foreground">
                {missing > 0 ? `${missing} still to fill in` : 'Every department has a number'}
              </span>
              <Button onClick={() => void save()} loading={saving}>Save</Button>
            </div>
          ) : (
            <p className="m-0 text-xs text-muted-foreground">
              The plan is fixed while the first stage is being priced. Your consultant can change it.
            </p>
          )}
        </div>

        {scope.people_mentioned.length > 0 && scope.editable && (
          <div className="space-y-2 border-t border-border pt-4">
            <p className="m-0 text-sm font-medium text-foreground">People you mentioned</p>
            {scope.people_mentioned.map((p) =>
              adding === p.index ? (
                <form
                  key={p.index}
                  className="grid gap-2 rounded-md border border-border p-3 sm:grid-cols-2"
                  onSubmit={(e) => {
                    e.preventDefault();
                    void onConfirmPerson(p.index, person).then(() => setAdding(null));
                  }}
                >
                  <Select
                    label="Take part as"
                    value={person.participant_type}
                    options={[
                      { value: 'EMPLOYEE', label: 'Staff — knows the day-to-day work' },
                      { value: 'KEY_PERSON', label: 'Manager — we should speak with them too' },
                    ]}
                    onChange={(e) => setPerson({ ...person, participant_type: e.target.value as LeadershipPersonInput['participant_type'] })}
                  />
                  <Input label="Name" required value={person.name} onChange={(e) => setPerson({ ...person, name: e.target.value })} />
                  <Input label="Role" value={person.role_title ?? ''} onChange={(e) => setPerson({ ...person, role_title: e.target.value })} />
                  <Input label="Department" value={person.department ?? ''} onChange={(e) => setPerson({ ...person, department: e.target.value })} />
                  <Input label="Email" type="email" value={person.email ?? ''} onChange={(e) => setPerson({ ...person, email: e.target.value })} />
                  <Input label="Mobile" value={person.phone_e164 ?? ''} onChange={(e) => setPerson({ ...person, phone_e164: e.target.value })} />
                  <div className="flex justify-end gap-2 sm:col-span-2">
                    <Button type="button" variant="ghost" onClick={() => setAdding(null)}>Cancel</Button>
                    <Button type="submit">Add</Button>
                  </div>
                </form>
              ) : (
                <div key={p.index} className="flex items-center justify-between gap-3 rounded-md bg-muted/50 px-3 py-2">
                  <div className="min-w-0 text-sm">
                    <span className="font-medium text-foreground">{p.name || p.role || 'Someone'}</span>
                    <span className="text-muted-foreground">
                      {[p.role && p.name ? p.role : null, p.department].filter(Boolean).map((s) => ` · ${s}`)}
                    </span>
                  </div>
                  <div className="flex shrink-0 gap-1">
                    <Button size="sm" variant="secondary" icon={<UserPlus className="h-3.5 w-3.5" />} onClick={() => startAdding(p.index)}>
                      Add
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => void onDismissPerson(p.index)}>Not needed</Button>
                  </div>
                </div>
              )
            )}
          </div>
        )}

        {scope.planned_people.length > 0 && (
          <div className="space-y-1 border-t border-border pt-4">
            <p className="m-0 text-sm font-medium text-foreground">Already in the plan</p>
            <ul className="m-0 list-none space-y-1 p-0 text-sm text-muted-foreground">
              {scope.planned_people.map((p) => (
                <li key={p.id}>
                  {p.name}
                  {p.department ? ` · ${p.department}` : ''}
                  {p.participant_type === 'KEY_PERSON' ? ' · manager' : ''}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </Card>
  );
}
