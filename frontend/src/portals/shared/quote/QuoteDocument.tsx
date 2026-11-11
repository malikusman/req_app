import type { QuoteLine, QuoteScope } from '../../../lib/api';
import { formatMoney } from '../../../lib/money';

/**
 * The body of a Stage 1 proposal as the client reads it (Doc 17 §10): the
 * price line by line with VAT shown on its own, the additional-participant
 * rate, what is and isn't included, and what happens next. Shared by the
 * client's proposal page, the consultant's view and the administrator's
 * preview — it takes only client fields, so it can't show anything internal.
 */
export interface QuoteDocumentProps {
  currency: string;
  lineItems: QuoteLine[];
  subtotal: string;
  taxRate: string;
  taxAmount: string;
  total: string;
  additionalParticipantRate: string;
  scope: QuoteScope;
  paymentTerms?: string | null;
  termsReference?: string | null;
}

export function QuoteDocument({
  currency,
  lineItems,
  subtotal,
  taxRate,
  taxAmount,
  total,
  additionalParticipantRate,
  scope,
  paymentTerms,
  termsReference,
}: QuoteDocumentProps) {
  const money = (amount: string) => formatMoney(amount, currency);
  const vat = `${Number((Number(taxRate) * 100).toFixed(2))}%`;

  return (
    <div className="space-y-6">
      <section aria-label="The price">
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs text-text-secondary">
              <th className="py-2 font-medium">Item</th>
              <th className="py-2 text-right font-medium">Quantity</th>
              <th className="py-2 text-right font-medium">Amount</th>
            </tr>
          </thead>
          <tbody>
            {lineItems.map((line) => (
              <tr key={line.key} className="border-b border-border align-top">
                <td className="py-2.5 pr-4">
                  <p className="m-0 font-medium text-text-primary">{line.label}</p>
                  {line.detail ? <p className="m-0 text-xs text-text-secondary">{line.detail}</p> : null}
                </td>
                <td className="whitespace-nowrap py-2.5 pl-3 text-right tabular-nums text-text-secondary">{line.quantity}</td>
                <td className="whitespace-nowrap py-2.5 pl-3 text-right tabular-nums text-text-primary">{money(line.amount)}</td>
              </tr>
            ))}
            <tr className="border-b border-border">
              <td className="py-2.5 text-text-secondary">Subtotal</td>
              <td />
              <td className="whitespace-nowrap py-2.5 pl-3 text-right tabular-nums">{money(subtotal)}</td>
            </tr>
            <tr className="border-b border-border">
              <td className="py-2.5 text-text-secondary">VAT ({vat})</td>
              <td />
              <td className="whitespace-nowrap py-2.5 pl-3 text-right tabular-nums">{money(taxAmount)}</td>
            </tr>
            <tr>
              <td className="pt-3 text-base font-semibold text-text-primary">Total</td>
              <td />
              <td className="whitespace-nowrap pt-3 pl-3 text-right text-base font-semibold tabular-nums text-text-primary">{money(total)}</td>
            </tr>
          </tbody>
        </table>
        <p className="mt-3 text-sm text-text-secondary">
          Each additional person who takes part after this proposal: {money(additionalParticipantRate)}.
        </p>
      </section>

      <ScopeList title="What is included" items={scope.what_is_included} />
      {scope.participants_and_departments ? (
        <p className="m-0 text-sm text-text-secondary">{scope.participants_and_departments}</p>
      ) : null}
      <ScopeList title="What is not included" items={scope.what_is_not_included} />

      {scope.what_happens_next ? (
        <section>
          <h3 className="mb-1 text-sm font-semibold text-text-primary">What happens next</h3>
          <p className="m-0 text-sm text-text-secondary">{scope.what_happens_next}</p>
        </section>
      ) : null}

      <p className="m-0 text-xs text-text-secondary">
        {[scope.validity, paymentTerms, termsReference].filter(Boolean).join(' ')}
      </p>
    </div>
  );
}

function ScopeList({ title, items }: { title: string; items?: string[] }) {
  if (!items?.length) return null;
  return (
    <section>
      <h3 className="mb-1 text-sm font-semibold text-text-primary">{title}</h3>
      <ul className="m-0 list-disc space-y-1 pl-5 text-sm text-text-secondary">
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </section>
  );
}
