import { test, expect, type Page } from '@playwright/test';

// Stage 1 pricing (Doc 17) in the browser, across all three portals: the
// client waits while the proposal is prepared and can't invite staff; an
// administrator reviews the derivation and margin and approves; the client
// reads the proposal — nothing internal on it — and accepts, which opens team
// invitations; the consultant sees where it stands, without the margin.
//
// No model is needed: the seed sets the company to scripted P24 replies.
// Setup: `docker compose up`, then
//   docker compose exec rails bundle exec rails e2e:seed_pricing
// The tests run in order over one seeded engagement — seed again before re-running.

const CLIENT = {
  email: process.env.E2E_PRICING_EMAIL ?? 'pricing-e2e@mjadi.test',
  password: process.env.E2E_PRICING_PASSWORD ?? 'PricingE2E123!',
};
const ADMIN = { email: 'admin@reqapp.local', password: 'password123' };
const CONSULTANT = { email: 'consultant@reqapp.local', password: 'password123' };
const COMPANY = 'Pricing E2E Co';
// What would mean internal pricing reached a client or a consultant (Doc 17 §15).
const INTERNAL = /margin|fully loaded|consultant hours|internal cost|rate card/i;

test.describe.configure({ mode: 'serial' });

async function login(page: Page, portal: 'company' | 'platform' | 'consultant', who: { email: string; password: string }) {
  await page.goto(`/${portal}/login`);
  await page.getByRole('textbox', { name: 'Email' }).fill(who.email);
  await page.getByRole('textbox', { name: 'Password' }).fill(who.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(new RegExp(`/${portal}/dashboard`));
}

test.describe('Stage 1 pricing', () => {
  test('the client waits for the proposal and cannot invite staff yet', async ({ page }) => {
    await login(page, 'company', CLIENT);
    await expect(page.getByText(/preparing your Stage 1 proposal/i).first()).toBeVisible();

    await page.goto('/company/employees');
    await expect(page.getByText('Your team can be invited once the Stage 1 proposal is accepted.')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Send invite' })).toHaveCount(0);
  });

  test('an administrator reviews the derivation and margin, and approves', async ({ page }) => {
    await login(page, 'platform', ADMIN);
    await page.goto('/platform/pricing');
    await page.getByRole('cell', { name: COMPANY }).first().click();

    await expect(page.getByRole('heading', { name: new RegExp(`${COMPANY} — Stage 1 quote`) })).toBeVisible();
    await expect(page.getByText('How the fee was derived')).toBeVisible();
    await expect(page.getByText('against fully loaded cost')).toBeVisible();
    await expect(page.getByText(/placeholder values/)).toBeVisible();
    await expect(page.getByText('What the client will see')).toBeVisible();

    await page.getByRole('button', { name: 'Approve and issue' }).first().click();
    await page.getByRole('dialog').getByRole('button', { name: 'Approve and issue' }).click();
    await expect(page.getByText('With the client').first()).toBeVisible();

    // What it was priced from: the rate card and floor in effect, and their history.
    await page.goto('/platform/pricing');
    await page.getByRole('button', { name: 'Rates and margin floor' }).click();
    await expect(page.getByText(/Stage 1 rate card · v\d+/)).toBeVisible();
    await expect(page.getByText('Margin floor', { exact: true })).toBeVisible();
    await expect(page.getByText('Rate card history')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Make a new version' })).toBeVisible();
  });

  test('the client reads the proposal, with nothing internal on it, and accepts', async ({ page }) => {
    await login(page, 'company', CLIENT);
    await expect(page.getByText('Your Stage 1 proposal is ready').first()).toBeVisible();
    await page.getByRole('link', { name: 'Review and accept' }).or(page.getByRole('button', { name: 'Review and accept' })).first().click();

    await expect(page).toHaveURL(/\/company\/proposal/);
    await expect(page.getByText('What is included')).toBeVisible();
    await expect(page.getByText('What is not included')).toBeVisible();
    await expect(page.getByText(/Each additional person/)).toBeVisible();
    await expect(page.locator('main')).not.toContainText(INTERNAL);

    const accept = page.getByRole('button', { name: 'Accept the proposal' });
    await expect(accept).toBeDisabled();
    await page.getByRole('checkbox').check();
    await accept.click();

    await expect(page).toHaveURL(/\/company\/employees/);
    await expect(page.getByText(/Your Stage 1 proposal covers 3 people/)).toBeVisible();
    await expect(page.getByRole('button', { name: 'Send invite' })).toBeVisible();
  });

  test('the consultant sees where the proposal stands, without the margin', async ({ page }) => {
    await login(page, 'consultant', CONSULTANT);
    await page.getByRole('link', { name: COMPANY }).first().click();

    // The overview waits on several requests; a cold dev server takes a while.
    await expect(page.getByText('Stage 1 proposal', { exact: true })).toBeVisible({ timeout: 45_000 });
    await expect(page.getByText('Engagement: Stage 1 in progress')).toBeVisible();
    await expect(page.getByText('Accepted', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'What the client sees' }).click();
    await expect(page.getByText('What is included')).toBeVisible();
    await expect(page.locator('main')).not.toContainText(INTERNAL);
  });
});
