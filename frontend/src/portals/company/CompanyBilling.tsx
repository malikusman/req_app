import { useEffect, useState } from 'react';
import { api, type BillingSnapshot } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanyBilling() {
  const token = useCompanyToken();
  const [billing, setBilling] = useState<BillingSnapshot | null>(null);
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState('');

  const load = () => {
    if (!token) return;
    api.companyBilling(token).then(setBilling);
  };

  useEffect(() => {
    load();
    const params = new URLSearchParams(window.location.search);
    if (params.get('success')) {
      setMsg(params.get('mock') ? 'Mock subscription activated.' : 'Subscription updated successfully.');
      window.history.replaceState({}, '', '/company/billing');
      load();
    }
  }, [token]);

  const checkout = async (plan: string) => {
    if (!token) return;
    setLoading(true);
    try {
      const res = await api.startBillingCheckout(token, plan);
      window.location.href = res.checkout_url;
    } catch (err) {
      setMsg(err instanceof Error ? err.message : 'Checkout failed');
    } finally {
      setLoading(false);
    }
  };

  if (!billing) return <p>Loading…</p>;

  const sub = billing.subscription;
  const usage = billing.usage;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Billing</h1>
      <p style={{ color: '#64748b' }}>Manage your subscription and discovery conversation usage.</p>

      {msg && <div style={{ background: '#d1fae5', color: '#065f46', padding: '0.75rem', borderRadius: 8, marginBottom: '1rem' }}>{msg}</div>}

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <h3 style={{ marginTop: 0 }}>Current plan</h3>
        {sub ? (
          <>
            <p>
              <strong>{sub.plan}</strong> · {sub.status}
            </p>
            {sub.trial_ends_at && sub.status === 'trial' && (
              <p style={{ color: '#64748b' }}>Trial ends {new Date(sub.trial_ends_at).toLocaleDateString()}</p>
            )}
            {sub.current_period_ends_at && sub.status === 'active' && (
              <p style={{ color: '#64748b' }}>Renews {new Date(sub.current_period_ends_at).toLocaleDateString()}</p>
            )}
          </>
        ) : (
          <p>No subscription on file.</p>
        )}
        <p style={{ marginTop: '1rem' }}>
          Discovery conversations: <strong>{usage.conversations_used}</strong>
          {usage.conversation_limit != null ? ` / ${usage.conversation_limit}` : ' (unlimited)'}
          {usage.limit_reached && <span style={{ color: '#dc2626', marginLeft: 8 }}>Limit reached</span>}
        </p>
      </div>

      {(sub?.status === 'trial' || sub?.status === 'suspended') && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Upgrade</h3>
          {!billing.stripe_configured && (
            <p style={{ color: '#64748b', fontSize: '0.9rem' }}>Stripe not configured — mock checkout will activate plans locally.</p>
          )}
          <div className="grid-2">
            {billing.plans.map((plan) => (
              <div key={plan.id} className="card" style={{ margin: 0 }}>
                <h4 style={{ marginTop: 0, textTransform: 'capitalize' }}>{plan.id}</h4>
                <p style={{ color: '#64748b' }}>{plan.conversations} conversations</p>
                <p>
                  <strong>${(plan.amount_cents / 100).toFixed(0)}/mo</strong>
                </p>
                <button type="button" className="btn btn-primary" disabled={loading} onClick={() => checkout(plan.id)}>
                  {loading ? 'Redirecting…' : 'Subscribe'}
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
