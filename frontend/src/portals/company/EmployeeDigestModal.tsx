import { useEffect, useState } from 'react';
import {
  api,
  type Employee,
  type EmployeeValueDigest,
  type EmployeeValuePreference,
} from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { Button, Modal } from '../../components/ui';

const DIGEST_INTERESTS = ['approvals', 'automation', 'integrations', 'reporting', 'ai tools'] as const;

export function EmployeeDigestModal({
  employee,
  open,
  onClose,
}: {
  employee: Employee | null;
  open: boolean;
  onClose: () => void;
}) {
  const token = useCompanyToken();
  const [pref, setPref] = useState<EmployeeValuePreference | null>(null);
  const [latestDigest, setLatestDigest] = useState<EmployeeValueDigest | null>(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [acting, setActing] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    if (!open || !token || !employee) return;
    setLoading(true);
    setMessage('');
    setError('');
    api
      .employeeValuePreference(token, employee.id)
      .then((res) => {
        setPref(res.employee_value_preference);
        setLatestDigest(res.latest_digest);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load digest prefs'))
      .finally(() => setLoading(false));
  }, [open, token, employee?.id]);

  const toggleInterest = (interest: string) => {
    if (!pref) return;
    const current = pref.interests || [];
    const next = current.includes(interest) ? current.filter((i) => i !== interest) : [...current, interest];
    setPref({ ...pref, interests: next });
  };

  const savePrefs = async () => {
    if (!token || !employee || !pref) return;
    setSaving(true);
    setError('');
    setMessage('');
    try {
      const res = await api.updateEmployeeValuePreference(token, employee.id, {
        email_opt_in: pref.email_opt_in,
        frequency: pref.frequency || 'monthly',
        interests: pref.interests || [],
      });
      setPref(res.employee_value_preference);
      setLatestDigest(res.latest_digest);
      setMessage('Preferences saved.');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save preferences');
    } finally {
      setSaving(false);
    }
  };

  const generate = async () => {
    if (!token || !employee) return;
    setActing(true);
    setError('');
    setMessage('');
    try {
      const res = await api.generateEmployeeValueDigest(token, employee.id);
      setLatestDigest(res.digest);
      setMessage(`Draft digest generated for ${res.digest.period_key}.`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Generate failed');
    } finally {
      setActing(false);
    }
  };

  const send = async () => {
    if (!token || !employee) return;
    setActing(true);
    setError('');
    setMessage('');
    try {
      const res = await api.sendEmployeeValueDigest(token, employee.id);
      setLatestDigest(res.digest);
      setMessage(res.message || 'Digest queued.');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Send failed');
    } finally {
      setActing(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`Value digest — ${employee?.display_name || employee?.phone_e164 || ''}`}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Close
          </Button>
          <Button variant="secondary" loading={saving} onClick={savePrefs} disabled={!pref}>
            Save prefs
          </Button>
          <Button variant="secondary" loading={acting} onClick={generate}>
            Generate draft
          </Button>
          <Button loading={acting} onClick={send} disabled={!pref?.subscribed || !employee?.email}>
            Send test digest
          </Button>
        </>
      }
    >
      {loading || !pref ? (
        <p className="text-sm text-text-secondary">Loading preferences…</p>
      ) : (
        <div className="space-y-4 text-sm">
          {error && <p className="m-0 text-status-error">{error}</p>}
          {message && <p className="m-0 rounded-md bg-status-successBg px-3 py-2 text-status-success">{message}</p>}
          {!employee?.email && (
            <p className="m-0 text-xs text-status-error">Add an email on this employee before sending digests.</p>
          )}
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={!!pref.email_opt_in}
              onChange={(e) =>
                setPref({
                  ...pref,
                  email_opt_in: e.target.checked,
                  subscribed: e.target.checked,
                })
              }
            />
            Email opt-in for private value digests
          </label>
          <div>
            <div className="mb-1 text-xs font-medium uppercase tracking-wide text-text-secondary">Frequency</div>
            <select
              className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm"
              value={pref.frequency || 'monthly'}
              onChange={(e) => setPref({ ...pref, frequency: e.target.value })}
            >
              <option value="monthly">Monthly</option>
              <option value="twice_monthly">Twice monthly</option>
            </select>
          </div>
          <div>
            <div className="mb-2 text-xs font-medium uppercase tracking-wide text-text-secondary">Interests</div>
            <div className="flex flex-wrap gap-2">
              {DIGEST_INTERESTS.map((interest) => {
                const on = (pref.interests || []).includes(interest);
                return (
                  <button
                    key={interest}
                    type="button"
                    onClick={() => toggleInterest(interest)}
                    className={`rounded-full border px-3 py-1 text-xs ${
                      on ? 'border-primary bg-primary/10' : 'border-border'
                    }`}
                  >
                    {interest}
                  </button>
                );
              })}
            </div>
          </div>
          {latestDigest && (
            <div className="rounded-md border border-border p-3 text-xs">
              <div className="mb-1 font-medium">Latest digest</div>
              <div>
                {latestDigest.period_key} · {latestDigest.status}
                {latestDigest.delivery_status ? ` · ${latestDigest.delivery_status}` : ''}
              </div>
              {latestDigest.headline && <div className="mt-1">{latestDigest.headline}</div>}
              {Array.isArray(latestDigest.content?.tips) && (
                <ul className="mt-2 list-disc space-y-1 pl-4">
                  {(latestDigest.content?.tips as string[]).slice(0, 3).map((t) => (
                    <li key={t}>{t}</li>
                  ))}
                </ul>
              )}
            </div>
          )}
          <p className="m-0 text-xs text-text-secondary">
            Digests are private to the employee. Opt-in is required before Send test digest.
          </p>
        </div>
      )}
    </Modal>
  );
}
