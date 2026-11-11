import { useEffect, useState } from 'react';
import { api, type ConsultantStage1Quote } from '../../lib/api';
import { formatMoney } from '../../lib/money';
import { Badge, Button, Card } from '../../components/ui';
import { QuoteDocument } from '../shared/quote/QuoteDocument';
import { QUOTE_STATUS_LABELS, QUOTE_STATUS_VARIANTS, engagementStatusLabel } from '../platform/engagementStatus';

/**
 * Where the engagement and its Stage 1 proposal stand, for the consultant
 * (Doc 21 §44: consultants view quotes). What the client sees and the newest
 * version's status — never cost, hours or margin (Doc 17 §15).
 */
export function ConsultantProposalCard({ token, companyId }: { token: string; companyId: number }) {
  const [data, setData] = useState<ConsultantStage1Quote | null>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    api.consultantStage1Quote(token, companyId).then(setData).catch(() => setData(null));
  }, [token, companyId]);

  if (!data?.engagement_status) return null;
  const { latest, quote } = data;

  return (
    <Card title="Stage 1 proposal">
      <div className="space-y-2 text-sm">
        <p className="m-0 text-text-secondary">Engagement: {engagementStatusLabel(data.engagement_status)}</p>
        {latest ? (
          <div className="flex flex-wrap items-center gap-2">
            <span>Version {latest.version}</span>
            <Badge variant={QUOTE_STATUS_VARIANTS[latest.status]}>{QUOTE_STATUS_LABELS[latest.status]}</Badge>
          </div>
        ) : (
          <p className="m-0 text-text-secondary">No proposal worked out yet.</p>
        )}
        {latest?.rejection_note ? <p className="m-0">Sent back: {latest.rejection_note}</p> : null}
        {latest?.decline_reason ? <p className="m-0">The client’s reason: {latest.decline_reason}</p> : null}
        {quote ? (
          <>
            <p className="m-0">
              {formatMoney(quote.total, quote.currency)} including VAT · {quote.participants_included} people ·{' '}
              {quote.deep_dives_included} deep dives
            </p>
            <Button variant="secondary" size="sm" onClick={() => setOpen((v) => !v)}>
              {open ? 'Hide what the client sees' : 'What the client sees'}
            </Button>
            {open ? (
              <div className="mt-3 border-t border-border pt-3">
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
              </div>
            ) : null}
          </>
        ) : null}
      </div>
    </Card>
  );
}
