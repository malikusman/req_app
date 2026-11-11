import { test, expect, type Page } from '@playwright/test';

// Consolidation and synthesis (Doc 10) in the browser: the consultant reviews
// shared work counted once and leadership's view against staff evidence,
// every decision asks for a reason, and new evidence marks the synthesis
// stale; the client sees none of it.
//
// No model is needed: the seed sets the company to scripted synthesis replies.
// Setup: `docker compose up`, then
//   docker compose exec rails bundle exec rails e2e:seed_synthesis
// The tests run in order over one seeded engagement — seed again before re-running.

const CLIENT = {
  email: process.env.E2E_SYNTHESIS_EMAIL ?? 'synthesis-e2e@mjadi.test',
  password: process.env.E2E_SYNTHESIS_PASSWORD ?? 'SynthesisE2E123!',
};
const CONSULTANT = { email: 'consultant@reqapp.local', password: 'password123' };
const COMPANY = 'Synthesis E2E Co';
// What synthesis wrote, and what it must never show: consultant-private notes.
const SYNTHESIS = /One way of handling|Counted once|Staff evidence supports|SENTINEL-POLITICS/i;

test.describe.configure({ mode: 'serial' });

async function login(page: Page, portal: 'company' | 'consultant', who: { email: string; password: string }) {
  await page.goto(`/${portal}/login`);
  await page.getByRole('textbox', { name: 'Email' }).fill(who.email);
  await page.getByRole('textbox', { name: 'Password' }).fill(who.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(new RegExp(`/${portal}/dashboard`));
}

// The company's page in the consultant portal, by its link in the sidebar.
async function openCompany(page: Page): Promise<string> {
  await login(page, 'consultant', CONSULTANT);
  await page.getByRole('link', { name: COMPANY }).first().click();
  await expect(page).toHaveURL(/\/consultant\/companies\/\d+$/);
  return page.url();
}

async function openSynthesis(page: Page, companyUrl?: string) {
  const url = companyUrl ?? (await openCompany(page));
  await page.goto(`${url}/synthesis`);
  await expect(page.getByRole('heading', { name: 'Synthesis', level: 1 })).toBeVisible();
}

async function decide(page: Page, scope: ReturnType<Page['locator']>, label: string, reason: string) {
  await scope.getByRole('button', { name: label, exact: true }).click();
  await scope.getByLabel(new RegExp(`Why — ${label}`, 'i')).fill(reason);
  await scope.getByRole('button', { name: label, exact: true }).click();
}

test.describe('Synthesis', () => {
  test('the consultant confirms shared work, counted once, with a reason', async ({ page }) => {
    await openSynthesis(page);
    await expect(page.getByTestId('synthesis-status')).toContainText('waiting on you');

    const cluster = page.getByTestId('cluster-card').first();
    await expect(cluster).toContainText('Sales Coordinator');
    await expect(cluster).toContainText("Everyone's own estimates");
    await expect(cluster.getByTestId('cluster-dedup')).toContainText('h/yr');
    await expect(cluster).not.toContainText('E2E Person');

    // A decision needs a reason before it can be sent.
    await cluster.getByRole('button', { name: 'Confirm', exact: true }).click();
    await expect(cluster.getByRole('button', { name: 'Confirm', exact: true })).toBeDisabled();
    await cluster.getByLabel(/Why — confirm/i).fill('Same quotation work, each coordinator for their own customers');
    await cluster.getByRole('button', { name: 'Confirm', exact: true }).click();
    await expect(page.getByText('Confirmed', { exact: true }).first()).toBeVisible();
  });

  test("the consultant sets leadership's view against staff evidence", async ({ page }) => {
    await openSynthesis(page);
    await page.getByRole('tab', { name: /Leadership vs evidence/ }).click();

    const card = page.getByTestId('validation-card').first();
    await expect(page.getByText('Quotes take too long to reach customers').first()).toBeVisible();
    await expect(card).toContainText('management importance high');
    await decide(page, card, 'Agree', 'Three coordinators describe the same wait on prices');
    await expect(page.getByText('Approved').first()).toBeVisible();

    await page.getByRole('tab', { name: /Opportunities/ }).click();
    const opportunity = page.getByTestId('opportunity-card').first();
    await expect(opportunity).toContainText('Management importance');
    await expect(opportunity).toContainText('Platform priority');
  });

  test('new evidence marks the synthesis stale until it runs again', async ({ page }) => {
    const companyUrl = await openCompany(page);
    await page.goto(`${companyUrl}/findings`);
    await expect(page.getByText('Part of:').first()).toBeVisible();
    await page.getByRole('button', { name: 'Approve' }).first().click();
    await expect(page.getByText('Approved').first()).toBeVisible();

    await openSynthesis(page, companyUrl);
    await expect(page.getByTestId('synthesis-status')).toContainText('New evidence has arrived');
    await page.getByRole('button', { name: 'Run again' }).click();
    await expect(page.getByTestId('synthesis-status')).toContainText(/queued/i);
  });

  test('the client sees nothing synthesis produced', async ({ page }) => {
    await login(page, 'company', CLIENT);
    await expect(page.locator('body')).not.toContainText(SYNTHESIS);
    for (const path of ['/company/leadership', '/company/reports']) {
      await page.goto(path);
      await expect(page.locator('body')).not.toContainText(SYNTHESIS);
    }
  });
});
