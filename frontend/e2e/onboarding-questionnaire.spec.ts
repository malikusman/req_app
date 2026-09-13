import { test, expect, type Page } from '@playwright/test';

// The questionnaire's hard parts are browser behaviour, not pure functions: the
// answers save themselves as you go, one question only appears once another is
// answered, and four questions build their inputs out of what you picked earlier.
// None of that can be proven by a request spec.
//
// Setup: `docker compose up`, then
//   docker compose exec rails bin/rails e2e:seed_questionnaire

const EMAIL = process.env.E2E_QUESTIONNAIRE_EMAIL ?? 'questionnaire-e2e@mjadi.test';
const PASSWORD = process.env.E2E_QUESTIONNAIRE_PASSWORD ?? 'QuestionnaireE2E123!';

async function login(page: Page) {
  await page.goto('/company/login');
  await page.getByRole('textbox', { name: 'Email' }).fill(EMAIL);
  await page.getByRole('textbox', { name: 'Password' }).fill(PASSWORD);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/\/company\/(dashboard|onboarding)/);
  await page.goto('/company/onboarding');
  // The questionnaire remembers which step you left on, so tests navigate
  // explicitly rather than assuming a starting point.
  await expect(stepNav(page).getByRole('button').first()).toBeVisible();
}

const stepNav = (page: Page) => page.getByRole('navigation', { name: 'Questionnaire steps' });

/**
 * The questionnaire has no Save button, so the status label is the signal. Waiting
 * for "Saved" alone is not enough: a change made while a save is in flight is
 * queued behind it, and the label from the first save is still on screen when the
 * second has yet to go out. Waiting for it to appear *and then clear* means a
 * cycle finished with nothing left queued — which is what makes a reload safe.
 */
async function saved(page: Page, action: () => Promise<void>) {
  await action();
  const label = page.getByText(/^Saved$/);
  await expect(label).toBeVisible({ timeout: 15_000 });
  await expect(label).toBeHidden({ timeout: 15_000 });
}

const choice = (page: Page, name: string | RegExp) =>
  page.getByRole('button', { name, exact: typeof name === 'string' });

/** A question, so a choice can be found even when another question offers the same word. */
const question = (page: Page, name: RegExp) => page.getByRole('group', { name });

/**
 * Answers persist between tests — that is the point of the feature — so a test
 * that toggles a choice has to state the outcome it wants rather than assume the
 * starting position.
 */
async function setChoice(page: Page, name: string, on: boolean, within?: ReturnType<typeof question>) {
  const button = (within ?? page).getByRole('button', { name, exact: true });
  const pressed = (await button.getAttribute('aria-pressed')) === 'true';
  if (pressed !== on) await button.click();
  await expect(button).toHaveAttribute('aria-pressed', String(on));
}

async function gotoStep(page: Page, step: number) {
  await stepNav(page).getByRole('button').nth(step - 1).click();
  await expect(page.getByText(new RegExp(`Step ${step} of 8`))).toBeVisible();
}

test.describe('company onboarding questionnaire', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('presents eight steps and says what the percentage means', async ({ page }) => {
    await expect(stepNav(page).getByRole('button')).toHaveCount(8);
    await gotoStep(page, 1);
    // Without this the bar reads as "you have not finished", when the optional
    // questions are deliberately never required.
    await expect(page.getByText(/essential questions only/i)).toBeVisible();
  });

  test('saves an answer without a save button', async ({ page }) => {
    await gotoStep(page, 1);
    await saved(page, () => setChoice(page, 'Businesses', false));

    await saved(page, () => setChoice(page, 'Businesses', true));
    await page.reload();
    await expect(choice(page, 'Businesses')).toHaveAttribute('aria-pressed', 'true');
  });

  test('reveals the documentation follow-up only once documentation exists', async ({ page }) => {
    await gotoStep(page, 2);
    const followUp = page.getByText('What types of process documentation are available?');

    await setChoice(page, 'We do not have formal process documentation', true);
    await expect(followUp).toBeHidden();

    await setChoice(page, 'Not sure', true, question(page, /how well documented are your/i));
    await expect(followUp).toBeHidden();

    await setChoice(page, 'Some processes are documented', true);
    await expect(followUp).toBeVisible();
  });

  test('builds headcount rows from the departments picked above', async ({ page }) => {
    await gotoStep(page, 2);
    const departments = question(page, /which departments or functions exist/i);

    await setChoice(page, 'Finance & Accounting', true, departments);
    await setChoice(page, 'Sales', true, departments);

    await expect(page.getByRole('spinbutton', { name: 'Headcount for Finance & Accounting' })).toBeVisible();
    await expect(page.getByRole('spinbutton', { name: 'Headcount for Sales' })).toBeVisible();

    // Removing a department must take its headcount row with it, or the answer
    // keeps a number for a department the company just said it does not have.
    await setChoice(page, 'Sales', false, departments);
    await expect(page.getByRole('spinbutton', { name: 'Headcount for Sales' })).toBeHidden();
  });

  test('takes a headcount, or "Not sure" instead', async ({ page }) => {
    await gotoStep(page, 2);
    await setChoice(page, 'Finance & Accounting', true, question(page, /which departments or functions exist/i));

    const input = page.getByRole('spinbutton', { name: 'Headcount for Finance & Accounting' });
    await saved(page, () => input.fill('12'));

    // Every row carries its own "Not sure", and Q10 offers one too — so the
    // button is addressed by the department it belongs to.
    await page.getByRole('button', { name: 'Not sure: Finance & Accounting' }).click();
    await expect(input).toBeDisabled();
  });

  test('offers a volume box for each high-volume activity picked', async ({ page }) => {
    await gotoStep(page, 3);
    // "invoices" is offered by more than one question on this step.
    await setChoice(page, 'invoices', true, question(page, /repeatedly or in particularly high volumes/i));

    const detail = page.getByRole('textbox', { name: 'How often: invoices' });
    await expect(detail).toBeVisible();
    await saved(page, () => detail.fill('500/day'));
  });

  test('asks for channels per party, not one flat list', async ({ page }) => {
    await gotoStep(page, 5);

    // Start from no parties chosen, so stage two genuinely has nothing to show.
    for (const party of ['customers / clients', 'suppliers / vendors']) {
      await setChoice(page, party, false);
    }
    await expect(page.getByText('How do you reach each one?')).toBeHidden();

    await setChoice(page, 'customers / clients', true);
    await setChoice(page, 'suppliers / vendors', true);
    await expect(page.getByText('How do you reach each one?')).toBeVisible();

    // Each party gets its own card, so the same channel appears once per party —
    // which is the whole point of asking this way.
    await expect(page.getByRole('button', { name: 'WhatsApp' })).toHaveCount(2);
  });

  test('asks the three improvements as three fields', async ({ page }) => {
    await gotoStep(page, 6);

    await saved(page, async () => {
      await page.getByRole('textbox', { name: 'First priority' }).fill('Stop re-keying invoices');
      await page.getByRole('textbox', { name: 'Second priority' }).fill('Faster approvals');
      await page.getByRole('textbox', { name: 'Third priority' }).fill('Better reporting');
    });

    // Three inputs, one answer: they have to come back in the order they were given.
    await page.reload();
    await gotoStep(page, 6);
    await expect(page.getByRole('textbox', { name: 'First priority' })).toHaveValue('Stop re-keying invoices');
    await expect(page.getByRole('textbox', { name: 'Third priority' })).toHaveValue('Better reporting');
  });

  test('offers a searchable system list per category', async ({ page }) => {
    await gotoStep(page, 4);

    await expect(page.getByText('ERP / core business system')).toBeVisible();
    await expect(page.getByText('Reporting / business intelligence')).toBeVisible();

    // A category already answered shows its choice instead of the search box.
    const clear = page.getByRole('button', { name: 'Clear ERP / core business system' });
    if (await clear.count()) await clear.click();

    await page.getByRole('textbox', { name: /ERP \/ core business system/ }).fill('odo');
    await saved(page, () => page.getByRole('button', { name: 'Odoo', exact: true }).click());

    await expect(clear).toBeVisible();
    await page.reload();
    await gotoStep(page, 4);
    await expect(page.getByRole('button', { name: 'Clear ERP / core business system' })).toBeVisible();
  });

  test('never shows the old brand name', async ({ page }) => {
    for (const step of [6, 8]) {
      await gotoStep(page, step);
      await expect(page.locator('body')).not.toContainText('Worktruth');
    }
    await expect(page.locator('body')).toContainText('Mjadi');
  });
});

test.describe('on a phone', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('the party/channel matrix stacks into cards and never scrolls sideways', async ({ page }) => {
    await login(page);
    await gotoStep(page, 5);
    await setChoice(page, 'customers / clients', true);
    await expect(page.getByText('How do you reach each one?')).toBeVisible();

    // The failure this guards against is a matrix laid out as a table: it fits at
    // 1440px and pushes the whole page sideways at 390px.
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    expect(overflow).toBeLessThanOrEqual(1);
  });

  test('headcount rows stay usable at phone width', async ({ page }) => {
    await login(page);
    await gotoStep(page, 2);
    await setChoice(page, 'Finance & Accounting', true, question(page, /which departments or functions exist/i));

    const input = page.getByRole('spinbutton', { name: 'Headcount for Finance & Accounting' });
    await expect(input).toBeVisible();
    const box = await input.boundingBox();
    // Anything under ~44px is hard to hit with a thumb.
    expect(box!.height).toBeGreaterThanOrEqual(40);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    );
    expect(overflow).toBeLessThanOrEqual(1);
  });
});
