import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanySettings() {
  const token = useCompanyToken();
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [security, setSecurity] = useState<{ active_access_codes: number; security_snapshot: Record<string, unknown> } | null>(null);
  const [msg, setMsg] = useState('');

  useEffect(() => {
    if (!token) return;
    api.companySettingsOrganization(token).then((d) => {
      setDisplayName(d.company.display_name || '');
      setLocale(d.company.locale);
    });
    api.companySettingsSecurity(token).then(setSecurity);
  }, [token]);

  const saveOrg = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    await api.updateCompanySettings(token, { display_name: displayName, locale });
    setMsg('Organization settings saved.');
  };

  const rotate = async () => {
    if (!token || !confirm('Rotate all employee access codes? Admins must redistribute new codes.')) return;
    const res = await api.rotateAccessCodes(token);
    setMsg(`Rotated ${res.codes_rotated} access codes.`);
    api.companySettingsSecurity(token).then(setSecurity);
  };

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Settings</h1>
      {msg && <div style={{ background: '#d1fae5', color: '#065f46', padding: '0.75rem', borderRadius: 8, marginBottom: '1rem' }}>{msg}</div>}

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <h3 style={{ marginTop: 0 }}>Organization</h3>
        <form onSubmit={saveOrg}>
          <div className="form-group">
            <label>Display name</label>
            <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
          </div>
          <div className="form-group">
            <label>Locale (reports)</label>
            <select value={locale} onChange={(e) => setLocale(e.target.value)}>
              <option value="en">English</option>
              <option value="es">Spanish</option>
            </select>
          </div>
          <button type="submit" className="btn btn-primary">
            Save
          </button>
        </form>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Security</h3>
        {security && (
          <>
            <p>Active access codes: <strong>{security.active_access_codes}</strong></p>
            <p style={{ color: '#64748b' }}>
              Unrecognized verification attempts (7d):{' '}
              {String(security.security_snapshot?.unrecognized_verification_attempts_7d ?? 0)}
            </p>
            <button type="button" className="btn btn-secondary" onClick={rotate}>
              Rotate all access codes
            </button>
          </>
        )}
      </div>
    </div>
  );
}
