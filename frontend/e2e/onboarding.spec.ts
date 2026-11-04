import { test, expect, type Page } from '@playwright/test';

// Company onboarding (Doc 07) is one screen whose hard parts are browser
// behaviour: answers save themselves, "Not sure" clears the other choices, the
// count rows follow the departments picked, a website proposal fills the form
// once confirmed, and a planned person is flagged when their department leaves
// the plan. None of that can be proven by a request spec.
//
// Setup: `docker compose up`, then
//   docker compose exec rails bundle exec rails e2e:seed_onboarding
// The tests run in order over one seeded key user, and the last one submits —
// seed again before re-running.

const EMAIL = process.env.E2E_ONBOARDING_EMAIL ?? 'onboarding-e2e@mjadi.test';
const PASSWORD = process.env.E2E_ONBOARDING_PASSWORD ?? 'OnboardingE2E123!';

test.describe.configure({ mode: 'serial' });

async function login(page: Page) {
  await page.goto('/company/login');
  await page.getByRole('textbox', { name: 'Email' }).fill(EMAIL);
  await page.getByRole('textbox', { name: 'Password' }).fill(PASSWORD);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/\/company\/onboarding/);
  await expect(page.getByRole('heading', { name: 'About the company' })).toBeVisible();
}

/**
 * There is no Save button, so the status label is the signal. Waiting for it to
 * appear *and then clear* means a save cycle finished with nothing left queued,
 * which is what makes a reload safe.
 */
async function saved(page: Page, action: () => Promise<void>) {
  await action();
  const label = page.getByText(/^Saved$/);
  await expect(label).toBeVisible({ timeout: 15_000 });
  await expect(label).toBeHidden({ timeout: 15_000 });
}

/** A question, so a choice can be found even when another question offers the same word. */
const question = (page: Page, name: RegExp) => page.getByRole('group', { name });

/** Answers persist between tests, so a test states the outcome it wants rather than assume it. */
async function setChoice(page: Page, within: ReturnType<typeof question>, name: string, on: boolean) {
  const button = within.getByRole('button', { name, exact: true });
  const pressed = (await button.getAttribute('aria-pressed')) === 'true';
  if (pressed !== on) await button.click();
  await expect(button).toHaveAttribute('aria-pressed', String(on));
}

test.describe('company onboarding', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('is one screen of facts, with nothing about goals, money or readiness', async ({ page }) => {
    for (const heading of ['About the company', 'How work arrives and where it lives', 'Who takes part']) {
      await expect(page.getByRole('heading', { name: heading })).toBeVisible();
    }
    await expect(page.getByRole('navigation', { name: 'Questionnaire steps' })).toHaveCount(0);
    await expect(page.getByRole('main')).not.toContainText(/revenue|budget|pain point|readiness|challenge/i);
  });

  test('fills the form from a website proposal once it is confirmed', async ({ page }) => {
    await expect(page.getByText('Wholesaler of tailoring materials')).toBeVisible();
    await expect(page.getByText(/one of the leading wholesalers of tailoring materials/)).toBeVisible();

    await page.getByRole('button', { name: 'Confirm', exact: true }).click();

    await expect(page.getByText('Confirmed', { exact: true })).toBeVisible();
    await expect(page.getByRole('textbox', { name: 'In a few words, what exactly do you do?' })).toHaveValue(
      'Wholesaler of tailoring materials'
    );
  });

  test('saves an answer without a save button', async ({ page }) => {
    const headcount = question(page, /how many people work in the company/i);
    await saved(page, () => setChoice(page, headcount, '11–50', true));

    await page.reload();
    await expect(question(page, /how many people work in the company/i).getByRole('button', { name: '11–50' })).toHaveAttribute(
      'aria-pressed',
      'true'
    );
  });

  test('"Not sure" clears the other choices', async ({ page }) => {
    const channels = question(page, /how do customers and partners mainly reach you/i);
    await setChoice(page, channels, 'WhatsApp', true);
    await saved(page, () => channels.getByRole('button', { name: 'Not sure', exact: true }).click());

    await expect(channels.getByRole('button', { name: 'WhatsApp', exact: true })).toHaveAttribute('aria-pressed', 'false');
    await expect(channels.getByRole('button', { name: 'Not sure', exact: true })).toHaveAttribute('aria-pressed', 'true');
  });

  test('asks how many people from each department picked to take part', async ({ page }) => {
    const departments = question(page, /which departments or functions exist/i);
    await setChoice(page, departments, 'Sales', true);
    await setChoice(page, departments, 'Finance', true);

    const taking = question(page, /which departments should take part/i);
    await setChoice(page, taking, 'Sales', true);
    await setChoice(page, taking, 'Finance', true);

    await saved(page, () => page.getByRole('spinbutton', { name: 'Headcount for Sales' }).fill('3'));
    const notSureFinance = page.getByRole('button', { name: 'Not sure: Finance' });
    await saved(page, () => notSureFinance.click());
    await expect(notSureFinance).toHaveAttribute('aria-pressed', 'true');
  });

  test('flags a planned person whose department no longer takes part', async ({ page }) => {
    await page.getByRole('button', { name: 'Add a person' }).click();
    await page.getByRole('textbox', { name: 'Name', exact: true }).fill('Rania Haddad');
    await page.getByRole('combobox', { name: 'Department' }).selectOption('Sales');
    await page.getByRole('button', { name: 'Add', exact: true }).click();
    await expect(page.getByText('Rania Haddad', { exact: true })).toBeVisible();

    await saved(page, () => setChoice(page, question(page, /which departments should take part/i), 'Sales', false));
    const warning = page.getByText('Sales is no longer one of the departments taking part.');
    await expect(warning).toBeVisible();

    await page.getByRole('combobox', { name: 'Move Rania Haddad to' }).selectOption('Finance');
    await expect(warning).toBeHidden();
    await expect(page.getByText('Rania Haddad', { exact: true }).locator('..')).toContainText('Finance');
  });

  test('never scrolls sideways on a phone', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.reload();
    await expect(page.getByRole('heading', { name: 'Who takes part' })).toBeVisible();

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test('needs the confidentiality acknowledgement, then hands over to the dashboard', async ({ page }) => {
    await page.getByRole('button', { name: 'Submit', exact: true }).click();
    await expect(page.getByText(/confidentiality acknowledgement/i)).toBeVisible();

    await page.getByRole('checkbox', { name: /I confirm I'm authorised/ }).check();
    await page.getByRole('button', { name: 'Submit', exact: true }).click();
    await expect(page).toHaveURL(/\/company\/dashboard/);
  });
});
