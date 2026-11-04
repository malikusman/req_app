import type { ReactNode } from 'react';
import { Card } from '../../components/ui';
import type { ProfileChangeEntry, ProfileProvenance } from '../../lib/api';

/** The confirmed company facts (Doc 07 §13), in the order onboarding asks for them. */
export const PROFILE_FIELDS: { key: string; label: string }[] = [
  { key: 'industry', label: 'Industry' },
  { key: 'industry_detail', label: 'What they do' },
  { key: 'size_band', label: 'Headcount' },
  { key: 'country', label: 'Headquarters' },
  { key: 'locations', label: 'Other locations' },
  { key: 'business_model', label: 'Business model' },
  { key: 'products_services', label: 'Products and services' },
  { key: 'org_departments', label: 'Departments' },
  { key: 'customer_channels', label: 'Customer channels' },
  { key: 'data_storage', label: 'Where data is kept' },
  { key: 'current_ai_use', label: 'AI tools in use' },
  { key: 'security_constraints', label: 'Constraints' },
];

/** Where each fact came from, so Mjadi staff can tell a confirmed fact from a typed one. */
export const PROVENANCE_LABELS: Record<string, string> = {
  PREFILL_CONFIRMED: 'confirmed from website',
  USER_ENTERED: 'entered by client',
  DISCOVERED_LATER: 'found in conversation',
  LEGACY_QUESTIONNAIRE: 'old questionnaire',
};

export function formatProfileValue(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value === 'string') return value.trim() || null;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (Array.isArray(value)) {
    const parts = value.map((v) => String(v).trim()).filter(Boolean);
    return parts.length ? parts.join(', ') : null;
  }
  if (typeof value === 'object') {
    // The matrix questions (systems by category, parties and their channels,
    // headcount per department) store a keyed map.
    const parts = Object.entries(value as Record<string, unknown>)
      .map(([k, v]) => {
        const inner = Array.isArray(v)
          ? v.map((x) => String(x).trim()).filter(Boolean).join(', ')
          : String(v ?? '').trim();
        return inner ? `${k}: ${inner}` : null;
      })
      .filter(Boolean);
    return parts.length ? parts.join(' · ') : null;
  }
  return null;
}

export function CompanyProfileSummary({
  profile: rawProfile,
  provenance: rawProvenance,
  action,
}: {
  profile?: Record<string, unknown> | null;
  provenance?: ProfileProvenance | null;
  /** Shown in the card's header, e.g. an Edit button. */
  action?: ReactNode;
}) {
  const profile = rawProfile || {};
  const provenance = rawProvenance || {};
  const rows = PROFILE_FIELDS.flatMap(({ key, label }) => {
    const source = provenance[key];
    const value = source?.unknown ? 'Not sure' : formatProfileValue(profile[key]);
    if (!value) return [];
    return [{ label, value, source: source ? PROVENANCE_LABELS[source.source] : undefined }];
  });

  return (
    <Card title="Company profile" action={action}>
      {rows.length === 0 ? (
        <p className="m-0 text-sm text-text-secondary">No confirmed facts yet.</p>
      ) : (
        <dl className="m-0 grid gap-3 sm:grid-cols-2">
          {rows.map((row) => (
            <div key={row.label}>
              <dt className="text-xs font-medium uppercase tracking-wide text-text-secondary">{row.label}</dt>
              <dd className="mt-0.5 text-sm text-text-primary">
                {row.value}
                {row.source && <span className="ml-1 text-xs text-text-secondary">· {row.source}</span>}
              </dd>
            </div>
          ))}
        </dl>
      )}
    </Card>
  );
}

const CHANGE_FIELD_LABELS: Record<string, string> = {
  ...Object.fromEntries(PROFILE_FIELDS.map(({ key, label }) => [key, label])),
  website_url: 'Website',
  company_systems: 'Systems',
};

const ACTOR_LABELS: Record<string, string> = {
  CompanyUser: 'client',
  ConsultantUser: 'consultant',
  PlatformUser: 'Mjadi',
};

const changeValue = (value: unknown) => (value === 'UNKNOWN' ? 'Not sure' : formatProfileValue(value) ?? '—');

/** Changes to the company's facts since onboarding was submitted, newest first. */
export function ProfileChanges({ changes }: { changes?: ProfileChangeEntry[] | null }) {
  if (!changes?.length) return null;

  return (
    <Card title="Changes since onboarding">
      <ul className="m-0 list-none space-y-2 p-0 text-sm">
        {changes.map((c) => (
          <li key={c.id} className="rounded-lg border border-border px-3 py-2">
            <span className="font-medium text-text-primary">{CHANGE_FIELD_LABELS[c.field] ?? c.field}</span>
            <span className="text-text-secondary">
              {' · '}
              {changeValue(c.from)} → {changeValue(c.to)}
            </span>
            <span className="block text-xs text-text-secondary">
              {[
                c.actor && `${c.actor.name ?? 'Someone'} (${ACTOR_LABELS[c.actor.type] ?? c.actor.type})`,
                PROVENANCE_LABELS[c.source],
                new Date(c.at).toLocaleDateString(undefined, { day: 'numeric', month: 'short' }),
              ]
                .filter(Boolean)
                .join(' · ')}
            </span>
          </li>
        ))}
      </ul>
    </Card>
  );
}
