import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type Employee } from '../../lib/api';
import { useCompanyToken, useAuth } from '../../lib/auth';

export function CompanyOnboarding() {
  const token = useCompanyToken();
  const { session, setSession } = useAuth();
  const navigate = useNavigate();
  const [step, setStep] = useState(1);
  const [displayName, setDisplayName] = useState('');
  const [locale, setLocale] = useState('en');
  const [phone, setPhone] = useState('');
  const [name, setName] = useState('');
  const [department, setDepartment] = useState('');
  const [invited, setInvited] = useState<(Employee & { access_code?: string })[]>([]);
  const [lastCode, setLastCode] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    api.companyOnboarding(token).then((d) => {
      setStep(d.step);
      setDisplayName(d.company.display_name || '');
      setLocale(d.company.locale || 'en');
    });
  }, [token]);

  const saveProfile = async () => {
    if (!token) return;
    setError('');
    try {
      const res = await api.updateOnboardingProfile(token, displayName, locale);
      setStep(res.step);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save');
    }
  };

  const inviteEmployee = async () => {
    if (!token || !phone) return;
    setError('');
    try {
      const res = await api.inviteEmployee(token, phone, name || undefined, department || undefined);
      setLastCode(res.access_code);
      setInvited((prev) => [...prev, { ...res.employee, access_code: res.access_code }]);
      setPhone('');
      setName('');
      setDepartment('');
      setStep(3);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to invite');
    }
  };

  const finish = async () => {
    if (!token) return;
    await api.completeOnboarding(token);
    if (session?.portal === 'company') {
      setSession({
        ...session,
        company: { ...session.company, portal_onboarding_completed_at: new Date().toISOString() },
      });
    }
    navigate('/company/dashboard');
  };

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Welcome — let&apos;s get started</h1>
      <p style={{ color: '#64748b' }}>Set up your company in three quick steps.</p>

      <div className="wizard-steps">
        {[1, 2, 3].map((s) => (
          <div key={s} className={`wizard-step ${s < step ? 'done' : ''} ${s === step ? 'active' : ''}`} />
        ))}
      </div>

      {error && <div className="error">{error}</div>}

      {step === 1 && (
        <div className="card">
          <h2 style={{ marginTop: 0 }}>Step 1 — Company profile</h2>
          <div className="form-group">
            <label>Display name</label>
            <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="Acme Corporation" />
          </div>
          <div className="form-group">
            <label>Default language (for reports)</label>
            <select value={locale} onChange={(e) => setLocale(e.target.value)}>
              <option value="en">English</option>
              <option value="es">Spanish</option>
              <option value="fr">French</option>
              <option value="de">German</option>
            </select>
          </div>
          <button type="button" className="btn btn-primary" onClick={saveProfile}>
            Continue
          </button>
        </div>
      )}

      {step === 2 && (
        <div className="card">
          <h2 style={{ marginTop: 0 }}>Step 2 — Invite employees</h2>
          <p style={{ color: '#64748b' }}>
            We suggest starting with <strong>3–5 employees per department</strong> for meaningful insights.
          </p>
          <div className="form-group">
            <label>Phone (E.164, e.g. +14155551234)</label>
            <input value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>
          <div className="form-group">
            <label>Name (optional)</label>
            <input value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="form-group">
            <label>Department (optional)</label>
            <input value={department} onChange={(e) => setDepartment(e.target.value)} placeholder="finance" />
          </div>
          <button type="button" className="btn btn-primary" onClick={inviteEmployee} disabled={!phone}>
            Invite & generate access code
          </button>
          {lastCode && (
            <div style={{ marginTop: '1rem' }}>
              <p>Latest access code (share privately — not via WhatsApp template):</p>
              <div className="code-box">{lastCode}</div>
            </div>
          )}
          {invited.length > 0 && (
            <button type="button" className="btn btn-secondary" style={{ marginTop: '1rem' }} onClick={() => setStep(3)}>
              Continue to instructions ({invited.length} invited)
            </button>
          )}
        </div>
      )}

      {step >= 3 && (
        <div className="card">
          <h2 style={{ marginTop: 0 }}>Step 3 — Share instructions</h2>
          <p>Employees should message your WhatsApp bot and enter their <strong>personal access code</strong> when prompted.</p>
          <ul style={{ color: '#475569', lineHeight: 1.8 }}>
            <li>Share the bot number with each invited employee</li>
            <li>Send each person their unique access code via email or Slack</li>
            <li>Never post access codes in public channels</li>
          </ul>
          {invited.length > 0 && (
            <div style={{ marginTop: '1rem' }}>
              <h4>Invited employees</h4>
              <ul>
                {invited.map((e) => (
                  <li key={e.id}>
                    {e.display_name || e.phone_e164} — code: <code>{e.access_code}</code>
                  </li>
                ))}
              </ul>
            </div>
          )}
          <button type="button" className="btn btn-primary" onClick={finish}>
            Go to dashboard
          </button>
        </div>
      )}
    </div>
  );
}
