import { useEffect, useState } from 'react';
import { api, type BillingSnapshot } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Button, StatCard, Skeleton, EmptyState } from '../../components/ui';

export function CompanyBilling() {
  const token = useCompanyToken();
  const [billing, setBilling] = useState<BillingSnapshot | null>(null);
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState('');
  const [initialLoading, setInitialLoading] = useState(true);

  const load = () => {
    if (!token) return;
    api
      .companyBilling(token)
      .then(setBilling)
      .finally(() => setInitialLoading(false));
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

  if (initialLoading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!billing) {
    return (
      <div className="space-y-6">
        <PageHeader title="Billing" description="Manage your subscription and discovery conversation usage." />
        <EmptyState title="Unable to load billing" description="Try refreshing the page." />
      </div>
    );
  }

  const sub = billing.subscription;
  const usage = billing.usage;

  return (
    <div className="space-y-6">
      <PageHeader title="Billing" description="Manage your subscription and discovery conversation usage." />
      {msg && <p className="rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">{msg}</p>}

      <Card title="Current plan">
        {sub ? (
          <div className="space-y-2 text-sm text-text-primary">
            <p className="m-0">
              <strong className="capitalize">{sub.plan}</strong> · {sub.status}
            </p>
            {sub.trial_ends_at && sub.status === 'trial' && (
              <p className="m-0 text-text-secondary">Trial ends {new Date(sub.trial_ends_at).toLocaleDateString()}</p>
            )}
            {sub.current_period_ends_at && sub.status === 'active' && (
              <p className="m-0 text-text-secondary">
                Renews {new Date(sub.current_period_ends_at).toLocaleDateString()}
              </p>
            )}
          </div>
        ) : (
          <p className="text-text-secondary">No subscription on file.</p>
        )}
        <div className="mt-4">
          <StatCard
            label="Discovery conversations"
            value={
              usage.conversation_limit != null
                ? `${usage.conversations_used} / ${usage.conversation_limit}`
                : `${usage.conversations_used} (unlimited)`
            }
          />
          {usage.limit_reached && (
            <p className="mt-2 text-sm text-status-error">Conversation limit reached</p>
          )}
        </div>
      </Card>

      {(sub?.status === 'trial' || sub?.status === 'suspended') && (
        <Card title="Upgrade">
          {!billing.stripe_configured && (
            <p className="text-sm text-text-secondary">Stripe not configured — mock checkout will activate plans locally.</p>
          )}
          <div className="mt-4 grid gap-4 md:grid-cols-2">
            {billing.plans.map((plan) => (
              <Card key={plan.id}>
                <h4 className="m-0 capitalize text-text-primary">{plan.id}</h4>
                <p className="text-sm text-text-secondary">{plan.conversations} conversations</p>
                <p className="text-lg font-semibold text-text-primary">${(plan.amount_cents / 100).toFixed(0)}/mo</p>
                <Button className="mt-3" loading={loading} disabled={loading} onClick={() => checkout(plan.id)}>
                  Subscribe
                </Button>
              </Card>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}
