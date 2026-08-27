import { Link } from 'react-router-dom';
import { MarketingLayout } from '../components/layout/MarketingLayout';
import { MarketingNav } from './MarketingNav';
import { MarketingFooter } from './sections/MarketingFooter';
import { BRAND_NAME, SALES_EMAIL } from './content';

export function PrivacyPage() {
  return (
    <MarketingLayout>
      <MarketingNav />
      <main className="border-b border-marketing-border bg-marketing-surface px-6 py-20 md:px-12 md:py-24">
        <article className="mx-auto max-w-3xl">
          <p className="text-label-caps text-marketing-accent">Legal</p>
          <h1 className="mt-2 font-display text-page-title text-marketing-foreground">Privacy</h1>
          <p className="mt-4 text-lg text-marketing-muted">
            How {BRAND_NAME} handles employee conversations, documents, and company data during operational discovery.
          </p>

          <div className="mt-10 space-y-8 text-sm leading-relaxed text-marketing-muted">
            <section>
              <h2 className="font-display text-lg font-semibold text-marketing-foreground">What we process</h2>
              <p className="mt-2">
                Company admins upload process documents and invite employees. Employees may share text, voice notes,
                images, and files via WhatsApp or web chat after consent. We process that content to extract structured
                signals, patterns, and reports for the customer that invited them.
              </p>
            </section>
            <section>
              <h2 className="font-display text-lg font-semibold text-marketing-foreground">Access & roles</h2>
              <p className="mt-2">
                Access is scoped by portal: company admins see their tenant; assigned expert consultants see assigned
                companies; platform operators manage trials and system health. Report share links are tokenized and
                access is logged.
              </p>
            </section>
            <section>
              <h2 className="font-display text-lg font-semibold text-marketing-foreground">Retention & deletion</h2>
              <p className="mt-2">
                Document purge removes file bytes and related chunks and re-aggregates intelligence. Conversation and
                employee retention follow the customer&apos;s engagement and contractual terms. For deletion or export
                requests (DSAR-style), contact your company admin or email{' '}
                <a className="text-marketing-accent underline" href={`mailto:${SALES_EMAIL}`}>
                  {SALES_EMAIL}
                </a>
                .
              </p>
            </section>
            <section>
              <h2 className="font-display text-lg font-semibold text-marketing-foreground">Contact</h2>
              <p className="mt-2">
                Privacy and sales inquiries:{' '}
                <a className="text-marketing-accent underline" href={`mailto:${SALES_EMAIL}`}>
                  {SALES_EMAIL}
                </a>
                . This page is a product summary — enterprise customers receive a DPA as part of contracting.
              </p>
            </section>
            <p>
              <Link to="/" className="text-marketing-accent underline">
                ← Back to home
              </Link>
            </p>
          </div>
        </article>
      </main>
      <MarketingFooter />
    </MarketingLayout>
  );
}
