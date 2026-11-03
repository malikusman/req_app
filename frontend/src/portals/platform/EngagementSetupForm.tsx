import { useEffect, useState, type FormEvent } from 'react';
import { api, type ConsultantUser, type EngagementSetupInput } from '../../lib/api';
import { DEPARTMENT_OPTIONS, toggleMulti } from '../../lib/companyProfileOptions';
import { Button, Input, Select } from '../../components/ui';
import { cn } from '../../lib/cn';

const LANGUAGES = [
  { code: 'en', label: 'English' },
  { code: 'ar', label: 'Arabic' },
];

export type EngagementSetupInitial = Partial<Omit<EngagementSetupInput, 'key_user'>> & {
  key_user?: Partial<EngagementSetupInput['key_user']>;
};

/**
 * Mjadi's engagement set-up (Doc 07 §3, S1–S8). Used to create an engagement,
 * and to approve a sign-up request — then the company and the key user come
 * from the request and only the engagement details are entered here.
 */
export function EngagementSetupForm({
  token,
  initial,
  fromRequest = false,
  submitLabel,
  onSubmit,
  onCancel,
}: {
  token: string;
  initial?: EngagementSetupInitial;
  /** The company and key user already exist: show them, don't edit them. */
  fromRequest?: boolean;
  submitLabel: string;
  onSubmit: (input: EngagementSetupInput) => Promise<void>;
  onCancel: () => void;
}) {
  const [form, setForm] = useState<EngagementSetupInput>({
    company_name: initial?.company_name ?? '',
    website_url: initial?.website_url ?? '',
    scope_type: initial?.scope_type ?? 'COMPANY',
    departments_in_scope: initial?.departments_in_scope ?? [],
    key_user: {
      name: initial?.key_user?.name ?? '',
      role_title: initial?.key_user?.role_title ?? '',
      email: initial?.key_user?.email ?? '',
      phone: initial?.key_user?.phone ?? '',
    },
    lead_consultant_id: initial?.lead_consultant_id ?? null,
    languages: initial?.languages ?? ['en'],
    proposal_reference: initial?.proposal_reference ?? '',
  });
  const [otherDepartment, setOtherDepartment] = useState('');
  const [consultants, setConsultants] = useState<ConsultantUser[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api
      .platformConsultants(token)
      .then((d) => setConsultants(d.consultants.filter((c) => c.status === 'active')))
      .catch(() => setError('Could not load consultants.'));
  }, [token]);

  const set = <K extends keyof EngagementSetupInput>(key: K, value: EngagementSetupInput[K]) =>
    setForm((f) => ({ ...f, [key]: value }));
  const setKeyUser = (key: keyof EngagementSetupInput['key_user'], value: string) =>
    setForm((f) => ({ ...f, key_user: { ...f.key_user, [key]: value } }));

  const departmentChoices = Array.from(new Set([...DEPARTMENT_OPTIONS, ...form.departments_in_scope]));

  const addOtherDepartment = () => {
    const name = otherDepartment.trim();
    if (name && !form.departments_in_scope.includes(name)) set('departments_in_scope', [...form.departments_in_scope, name]);
    setOtherDepartment('');
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    if (form.scope_type === 'DEPARTMENT' && form.departments_in_scope.length === 0) {
      setError('Choose the departments this engagement covers.');
      return;
    }
    if (form.languages.length === 0) {
      setError('Choose at least one language.');
      return;
    }
    if (!form.lead_consultant_id) {
      setError('Choose a lead consultant.');
      return;
    }
    setSaving(true);
    try {
      await onSubmit({
        ...form,
        departments_in_scope: form.scope_type === 'DEPARTMENT' ? form.departments_in_scope : [],
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save the engagement');
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      {error && <p className="m-0 text-sm text-destructive">{error}</p>}

      <fieldset className="space-y-3">
        <legend className="mb-1 text-sm font-medium">Company</legend>
        {fromRequest ? (
          <p className="m-0 text-sm">{form.company_name}</p>
        ) : (
          <Input label="Company name" value={form.company_name} onChange={(e) => set('company_name', e.target.value)} required />
        )}
        <div>
          <Input
            label="Website"
            value={form.website_url}
            onChange={(e) => set('website_url', e.target.value)}
            placeholder="company.com"
          />
          <p className="m-0 mt-1 text-xs text-muted-foreground">
            Strongly recommended — we read it to fill in most of the client&apos;s profile for them.
          </p>
        </div>
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="mb-1 text-sm font-medium">Scope</legend>
        <div className="flex gap-4 text-sm">
          {(['COMPANY', 'DEPARTMENT'] as const).map((scope) => (
            <label key={scope} className="flex items-center gap-2">
              <input type="radio" name="scope_type" checked={form.scope_type === scope} onChange={() => set('scope_type', scope)} />
              {scope === 'COMPANY' ? 'The whole company' : 'Some departments'}
            </label>
          ))}
        </div>
        {form.scope_type === 'DEPARTMENT' && (
          <div className="space-y-2">
            <div className="flex flex-wrap gap-2">
              {departmentChoices.map((d) => (
                <button
                  key={d}
                  type="button"
                  onClick={() => set('departments_in_scope', toggleMulti(form.departments_in_scope, d))}
                  className={cn(
                    'rounded-full border px-3 py-1 text-xs',
                    form.departments_in_scope.includes(d) ? 'border-primary bg-primary/10 text-primary' : 'border-border'
                  )}
                  aria-pressed={form.departments_in_scope.includes(d)}
                >
                  {d}
                </button>
              ))}
            </div>
            <div className="flex items-end gap-2">
              <Input label="Another department" value={otherDepartment} onChange={(e) => setOtherDepartment(e.target.value)} />
              <Button type="button" variant="secondary" size="sm" onClick={addOtherDepartment}>
                Add
              </Button>
            </div>
          </div>
        )}
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="mb-1 text-sm font-medium">Key user — the client's person for this engagement</legend>
        {fromRequest ? (
          <p className="m-0 text-sm">
            {form.key_user.name} · {form.key_user.email}
            {form.key_user.phone ? ` · ${form.key_user.phone}` : ''}
          </p>
        ) : (
          <>
            <Input label="Name" value={form.key_user.name} onChange={(e) => setKeyUser('name', e.target.value)} required />
            <Input label="Email" type="email" value={form.key_user.email} onChange={(e) => setKeyUser('email', e.target.value)} required />
            <Input label="Phone" value={form.key_user.phone} onChange={(e) => setKeyUser('phone', e.target.value)} placeholder="+971…" />
          </>
        )}
        <Input label="Role" value={form.key_user.role_title} onChange={(e) => setKeyUser('role_title', e.target.value)} placeholder="Operations Manager" />
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="mb-1 text-sm font-medium">Engagement</legend>
        <Select
          label="Lead consultant"
          value={form.lead_consultant_id ?? ''}
          onChange={(e) => set('lead_consultant_id', e.target.value ? Number(e.target.value) : null)}
          options={[{ value: '', label: 'Choose…' }, ...consultants.map((c) => ({ value: String(c.id), label: c.name }))]}
          required
        />
        <div>
          <p className="m-0 mb-1 text-sm">Languages</p>
          <div className="flex gap-4 text-sm">
            {LANGUAGES.map((l) => (
              <label key={l.code} className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={form.languages.includes(l.code)}
                  onChange={() => set('languages', toggleMulti(form.languages, l.code))}
                />
                {l.label}
              </label>
            ))}
          </div>
        </div>
        <Input
          label="Proposal reference"
          value={form.proposal_reference}
          onChange={(e) => set('proposal_reference', e.target.value)}
          placeholder="P-2026-014"
        />
      </fieldset>

      <p className="m-0 text-xs text-muted-foreground">
        Saving creates the client's account without a password and emails {fromRequest ? 'them' : 'the key user'} a link to
        set one. The link works for 7 days and can be sent again.
      </p>
      <div className="flex justify-end gap-2">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" loading={saving}>
          {submitLabel}
        </Button>
      </div>
    </form>
  );
}
