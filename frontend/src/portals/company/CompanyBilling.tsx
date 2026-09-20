import { useEffect, useState } from 'react';
import { api, type BillingSnapshot } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Button, Skeleton, EmptyState, ErrorNotice} from '../../components/ui';
import { cn } from '../../lib/cn';

export function CompanyBilling() {
  const token = useCompanyToken();
  const [billing, setBilling] = useState<BillingSnapshot | null>(null);
  const [loading, setLoading] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [loadError, setLoadError] = useState('');
  const [initialLoading, setInitialLoading] = useState(true);
  const [nowMs, setNowMs] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .companyBilling(token)
      .then(setBilling)
      .catch((err) => setLoadError(err instanceof Error ? err.message : 'Could not load billing information.'))
      .finally(() => setInitialLoading(false));
  };

  useEffect(() => {
    setNowMs(Date.now());
    load();
    const params = new URLSearchParams(window.location.search);
    if (params.get('success')) {
      setSuccessMsg(params.get('mock') ? 'Mock subscription activated.' : 'Subscription updated successfully.');
      window.history.replaceState({}, '', '/company/billing');
      load();
    }
  }, [token]);

  const checkout = async (plan: string) => {
    if (!token) return;
    setSuccessMsg('');
    setErrorMsg('');
    setLoading(true);
    try {
      const res = await api.startBillingCheckout(token, plan);
      window.location.href = res.checkout_url;
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Checkout failed');
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
        <PageHeader title="Billing" description="Your plan and discovery usage." />
        {loadError ? (
          <ErrorNotice message={loadError} onRetry={load} />
        ) : (
          <EmptyState title="No billing data" description="Billing details will appear once your subscription is set up." />
        )}
      </div>
    );
  }

  const sub = billing.subscription;
  const usage = billing.usage;

  /*
    plan and status are independent: plan is trial|starter|growth|enterprise,
    status is trial|active|suspended|churned. This page gated everything on
    `status === 'trial'`, but a trial customer reads plan="trial" with
    status="active" — so the trial end date never rendered and the upgrade
    options never appeared. A company whose trial had already expired saw a page
    that said "Trial · active" and nothing else.
  */
  const onTrial = sub?.plan === 'trial';
  const trialEnds = sub?.trial_ends_at ? new Date(sub.trial_ends_at) : null;
  // Read the clock in an effect, not during render — the render has to be pure,
  // and "has the trial ended" does not change while someone reads the page.
  const trialExpired = trialEnds != null && nowMs != null && trialEnds.getTime() < nowMs;
  const canUpgrade = Boolean(sub) && (onTrial || sub!.status === 'suspended');

  const limit = usage.conversation_limit;
  const pct = limit != null && limit > 0 ? Math.min(100, Math.round((usage.conversations_used / limit) * 100)) : null;
  const nearLimit = pct != null && pct >= 80;

  const fmt = (d: Date) => d.toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' });

  return (
    <div className="space-y-6">
      <PageHeader title="Billing" description="Your plan, what you have used, and what happens next." />
      {successMsg && (
        <p className="rounded-button bg-status-successBg px-4 py-2 text-sm text-status-success">{successMsg}</p>
      )}
      {errorMsg && <p className="rounded-button bg-status-errorBg px-4 py-2 text-sm text-status-error">{errorMsg}</p>}

      {trialExpired && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-warning/40 bg-warning/10 px-4 py-3 text-sm">
          <span className="text-foreground">
            Your trial ended on {fmt(trialEnds!)}. Discovery keeps working until you reach the conversation limit.
          </span>
        </div>
      )}

      <Card title="Current plan">
        {sub ? (
          <div className="grid gap-6 md:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]">
            <div className="space-y-1">
              <p className="m-0 font-display text-section-title capitalize text-foreground">{sub.plan}</p>
              <p className="m-0 text-sm text-muted-foreground">
                {sub.status === 'active' && !onTrial && 'Active subscription'}
                {sub.status === 'active' && onTrial && (trialExpired ? 'Trial period ended' : 'Trial in progress')}
                {sub.status === 'suspended' && 'Suspended — discovery is paused'}
                {sub.status === 'churned' && 'Cancelled'}
                {sub.status === 'trial' && 'Trial in progress'}
              </p>
              {trialEnds && onTrial && (
                <p className="m-0 text-sm text-muted-foreground">
                  {trialExpired ? 'Ended' : 'Ends'} {fmt(trialEnds)}
                </p>
              )}
              {sub.current_period_ends_at && !onTrial && (
                <p className="m-0 text-sm text-muted-foreground">
                  Renews {fmt(new Date(sub.current_period_ends_at))}
                </p>
              )}
            </div>

            {/* A bare "8 / 25" made you do the arithmetic. */}
            <div className="space-y-2">
              <div className="flex items-baseline justify-between gap-3">
                <span className="text-label-caps uppercase text-muted-foreground">Discovery conversations</span>
                <span className="text-sm text-muted-foreground">
                  {limit != null ? `${usage.remaining} remaining` : 'Unlimited'}
                </span>
              </div>
              <p className="m-0 font-display text-metric tabular-nums text-foreground">
                {usage.conversations_used}
                {limit != null && <span className="text-xl text-muted-foreground"> / {limit}</span>}
              </p>
              {pct != null && (
                <div
                  className="h-2 w-full overflow-hidden rounded-badge bg-muted"
                  role="progressbar"
                  aria-valuenow={pct}
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-label={`${usage.conversations_used} of ${limit} discovery conversations used`}
                >
                  <div
                    className={cn('h-full rounded-badge', usage.limit_reached || nearLimit ? 'bg-warning' : 'bg-accent')}
                    style={{ width: `${pct}%` }}
                  />
                </div>
              )}
              <p className="m-0 text-sm text-muted-foreground">
                {usage.limit_reached
                  ? 'Limit reached — new employees cannot start discovery until you add capacity.'
                  : 'A conversation counts when an employee starts discovery, not when you invite them.'}
              </p>
            </div>
          </div>
        ) : (
          <p className="text-muted-foreground">No subscription on file.</p>
        )}
      </Card>

      {canUpgrade && (
        <Card title={trialExpired ? 'Continue with a paid plan' : 'Plans'}>
          {!billing.stripe_configured && (
            <p className="m-0 text-sm text-muted-foreground">
              Card payments are not enabled on this environment yet — talk to us and we will set the plan up for you.
            </p>
          )}
          <div className="mt-4 grid gap-4 md:grid-cols-2">
            {billing.plans.map((plan) => (
              <div key={plan.id} className="flex flex-col gap-1 rounded-card border border-border p-5">
                <h4 className="m-0 font-display text-section-title capitalize text-foreground">{plan.id}</h4>
                <p className="m-0 font-display text-2xl font-bold tabular-nums text-foreground">
                  ${(plan.amount_cents / 100).toFixed(0)}
                  <span className="text-sm font-medium text-muted-foreground"> / month</span>
                </p>
                <p className="m-0 text-sm text-muted-foreground">
                  {plan.conversations.toLocaleString()} discovery conversations
                </p>
                <Button className="mt-3 self-start" loading={loading} disabled={loading} onClick={() => checkout(plan.id)}>
                  Choose {plan.id}
                </Button>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}
