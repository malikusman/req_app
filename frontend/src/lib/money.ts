/**
 * An amount as a client reads it: "AED 42,000", or "AED 2,287.50" when there
 * are cents. Mirrors Pricing::Money on the server, so the portal and the PDF
 * agree to the cent.
 */
export function formatMoney(amount: string | number | null | undefined, currency: string): string {
  const value = typeof amount === 'number' ? amount : Number(amount ?? 0);
  const whole = Number.isInteger(value);
  const figure = new Intl.NumberFormat('en-US', {
    minimumFractionDigits: whole ? 0 : 2,
    maximumFractionDigits: whole ? 0 : 2,
  }).format(value);
  return `${currency} ${figure}`;
}

/** A percentage given as a decimal string: "76.62" → "76.6%". */
export function formatPercent(value: string | number | null | undefined, digits = 1): string {
  const n = typeof value === 'number' ? value : Number(value ?? 0);
  return `${n.toFixed(digits)}%`;
}
