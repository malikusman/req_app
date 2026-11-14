import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type ClientQuote } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { formatMoney } from '../../lib/money';
import { Badge, Button, Card, EmptyState, ErrorNotice, Modal, PageHeader, Skeleton, Textarea } from '../../components/ui';
import { useToast } from '../../components/ui/ToastProvider';
import { QuoteDocument } from '../shared/quote/QuoteDocument';

function longDate(iso: string | null): string {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' });
}

/**
 * The client's Stage 1 proposal (Doc 17 §10, Doc 21 §10): the price, what it
 * includes and doesn't, and the rate for anyone added later. The key user
 * accepts it here, which starts Stage 1 and opens team invitations; or
 * declines it, saying why if they wish. Everyone else at the company can read
 * it. No countdowns, no pressure (Doc 17 §3.4).
 */
export function CompanyProposal() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [quote, setQuote] = useState<ClientQuote | null | undefined>(undefined);
  const [error, setError] = useState('');
  const [acknowledged, setAcknowledged] = useState(false);
  const [busy, setBusy] = useState(false);
  const [declining, setDeclining] = useState(false);
  const [reason, setReason] = useState('');
  const [actionError, setActionError] = useState('');

  const load = useCallback(() => {
    if (!token) return;
    api
      .companyStage1Quote(token)
      .then((d) => setQuote(d.quote))
      .catch((err) => setError(err instanceof Error ? err.message : 'Could not load your proposal'));
  }, [token]);

  useEffect(load, [load]);

  const download = async () => {
    if (!token || !quote) return;
    try {
      const { blob, filename } = await api.companyQuoteDocument(token, quote.id);
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = filename;
      link.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      toast({ title: err instanceof Error ? err.message : 'The proposal could not be downloaded', variant: 'error' });
    }
  };

  const accept = async () => {
    if (!token || !quote) return;
    setBusy(true);
    setActionError('');
    try {
      await api.companyAcceptQuote(token, quote.id);
      toast({ title: 'Proposal accepted', description: 'You can now invite your team.', variant: 'success' });
      navigate('/company/employees');
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'That didn’t work');
    } finally {
      setBusy(false);
    }
  };

  const decline = async () => {
    if (!token || !quote) return;
    setBusy(true);
    setActionError('');
    try {
      const d = await api.companyDeclineQuote(token, quote.id, reason);
      setQuote(d.quote);
      setDeclining(false);
      toast({ title: 'Thank you — your consultant will be in touch', variant: 'success' });
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'That didn’t work');
    } finally {
      setBusy(false);
    }
  };

  if (error) return <ErrorNotice message={error} onRetry={load} />;
  if (quote === undefined) return <Skeleton className="h-96 w-full" />;
  if (quote === null) {
    return (
      <div className="space-y-6">
        <PageHeader title="Your Stage 1 proposal" />
        <EmptyState
          title="We’re preparing your proposal"
          description="Your consultant is putting together the scope and fee for the first stage. You’ll be told as soon as it’s ready."
        />
      </div>
    );
  }

  const total = formatMoney(quote.total, quote.currency);
  const status = (() => {
    switch (quote.status) {
      case 'ACCEPTED':
        return { variant: 'success' as const, text: `Accepted${quote.accepted_by ? ` by ${quote.accepted_by}` : ''} on ${longDate(quote.accepted_at)}` };
      case 'DECLINED':
        return { variant: 'neutral' as const, text: `Declined on ${longDate(quote.declined_at)}` };
      case 'EXPIRED':
        return { variant: 'neutral' as const, text: 'Expired — your consultant will send a fresh one' };
      default:
        return quote.past_validity
          ? { variant: 'neutral' as const, text: 'Expired — your consultant will send a fresh one' }
          : { variant: 'info' as const, text: `Stands until ${longDate(quote.valid_until)}` };
    }
  })();

  return (
    <div className="space-y-6">
      <PageHeader
        title="Your Stage 1 proposal"
        description={`${quote.company_name} · version ${quote.version}${quote.issued_at ? ` · sent ${longDate(quote.issued_at)}` : ''}`}
        actions={
          <Button variant="secondary" size="sm" onClick={download}>
            Download PDF
          </Button>
        }
      />

      <div className="flex flex-wrap items-center gap-3">
        <p className="m-0 text-2xl font-semibold tabular-nums text-text-primary">{total}</p>
        <span className="text-sm text-text-secondary">including VAT</span>
        <Badge variant={status.variant}>{status.text}</Badge>
      </div>

      <Card>
        <QuoteDocument
          currency={quote.currency}
          lineItems={quote.line_items}
          subtotal={quote.subtotal}
          taxRate={quote.tax_rate}
          taxAmount={quote.tax_amount}
          total={quote.total}
          additionalParticipantRate={quote.additional_participant_rate}
          scope={quote.scope}
          paymentTerms={quote.payment_terms}
          termsReference={quote.terms_reference}
        />
      </Card>

      {quote.additional_participants && quote.additional_participants.count > 0 ? (
        <Card title="Added after your proposal">
          <p className="m-0 text-sm text-text-secondary">
            {quote.additional_participants.count} additional{' '}
            {quote.additional_participants.count === 1 ? 'person' : 'people'} ×{' '}
            {formatMoney(quote.additional_participants.rate, quote.currency)} ={' '}
            {formatMoney(quote.additional_participants.amount, quote.currency)}
          </p>
        </Card>
      ) : null}

      {quote.can_decide ? (
        <Card title="Your decision">
          <label className="flex items-start gap-2 text-sm text-text-primary">
            <input
              type="checkbox"
              className="mt-1"
              checked={acknowledged}
              onChange={(e) => setAcknowledged(e.target.checked)}
            />
            <span>I’ve read what’s included and the rate for anyone added later.</span>
          </label>
          {actionError && !declining ? <p className="mt-2 text-sm text-status-error">{actionError}</p> : null}
          <div className="mt-4 flex flex-wrap gap-2">
            <Button loading={busy && !declining} disabled={!acknowledged} onClick={accept}>
              Accept the proposal
            </Button>
            <Button variant="ghost" onClick={() => setDeclining(true)}>
              Decline
            </Button>
          </div>
          <p className="mt-3 text-xs text-text-secondary">
            Accepting starts Stage 1: you can then invite your team.
          </p>
        </Card>
      ) : quote.status === 'ISSUED' && !quote.past_validity ? (
        <p className="m-0 text-sm text-text-secondary">Your key user reviews and accepts the proposal.</p>
      ) : null}

      <Modal
        open={declining}
        onClose={() => setDeclining(false)}
        title="Decline the proposal"
        footer={
          <Button variant="danger" loading={busy} onClick={decline}>
            Decline
          </Button>
        }
      >
        <div className="space-y-3 text-sm">
          <p className="m-0 text-text-secondary">
            Your consultant will follow up. If you’d like, tell us why — it helps us come back with something that works.
          </p>
          <Textarea label="Your reason (optional)" value={reason} onChange={(e) => setReason(e.target.value)} />
          {actionError ? <p className="m-0 text-status-error">{actionError}</p> : null}
        </div>
      </Modal>
    </div>
  );
}
