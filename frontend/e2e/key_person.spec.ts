import { test, expect, type Page } from '@playwright/test';

// The conversation with leadership (Doc 08) in the browser: the dashboard leads
// with it and no longer suggests inviting staff; consent, one question at a
// time, pause and come back after a reload; the scope card settles a "Not sure"
// count; finishing hands over to pricing; and a manager's link opens only their
// own conversation.
//
// No model is needed: the seed sets the company to scripted replies.
// Setup: `docker compose up`, then
//   docker compose exec rails bundle exec rails e2e:seed_key_person
// The tests run in order over one seeded key user — seed again before re-running.

const EMAIL = process.env.E2E_KEY_PERSON_EMAIL ?? 'key-person-e2e@mjadi.test';
const PASSWORD = process.env.E2E_KEY_PERSON_PASSWORD ?? 'KeyPersonE2E123!';
const MANAGER_LINK = process.env.E2E_MANAGER_LINK ?? 'e2e-manager-link';
// Something only the key user says, to prove it never reaches the manager.
const OWN_WORDS = 'Quotations wait for my approval far too often here';

test.describe.configure({ mode: 'serial' });

async function login(page: Page) {
  await page.goto('/company/login');
  await page.getByRole('textbox', { name: 'Email' }).fill(EMAIL);
  await page.getByRole('textbox', { name: 'Password' }).fill(PASSWORD);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/\/company\/dashboard/);
}

const finished = (page: Page) => page.getByText(/everything we need/);

/** Sends one answer and waits for the reply (or the end). */
async function answer(page: Page, text: string) {
  const box = page.getByRole('textbox', { name: 'Your answer' });
  await box.fill(text);
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(box.or(finished(page)).first()).toBeVisible();
  await page.waitForFunction(() => !document.querySelector('textarea[disabled]'));
}

test.describe('the conversation with leadership', () => {
  test('the dashboard leads with the conversation, not with inviting staff', async ({ page }) => {
    await login(page);
    await expect(page.getByText('Your conversation with Mjadi').first()).toBeVisible();
    await expect(page.getByText(/invite your team/i)).toHaveCount(0);
    await expect(page.getByText('Rania Saleh')).toBeVisible();
    await expect(page.getByText('Invited', { exact: true })).toBeVisible();
  });

  test('starts after consent, and picks up the same thread after a pause and a reload', async ({ page }) => {
    await login(page);
    await page.goto('/company/leadership');
    await expect(page.getByText('Before we start')).toBeVisible();
    await expect(page.getByText(/isn't shown to colleagues/)).toBeVisible();
    await page.getByRole('button', { name: /let's start/ }).click();
    await expect(page.getByText(/Shall we start\?/)).toBeVisible();

    await answer(page, 'Yes, happy to start now.');
    await expect(page.getByText('Where do you want the business to be in two years that it isn’t today?'.replace('’', "'"))).toBeVisible();
    await answer(page, `${OWN_WORDS}, and we want to grow into Saudi.`);

    await page.getByRole('button', { name: 'Pause' }).click();
    await expect(page.getByText(/Everything is saved/)).toBeVisible();

    await page.reload();
    await expect(page.getByText(/^Welcome back\./).last()).toBeVisible();
    await expect(page.getByText(OWN_WORDS, { exact: false })).toBeVisible();
  });

  test('settles the unknown count on the scope card, finishes, and hands over to pricing', async ({ page }) => {
    // Up to 45 answers, each a round trip through the scripted replies: more than the default minute.
    test.setTimeout(240_000);
    await login(page);
    await page.goto('/company/leadership');
    for (let i = 0; i < 45; i += 1) {
      if (await finished(page).isVisible()) break;
      const salesCount = page.getByRole('textbox', { name: 'People from Sales' });
      if ((await salesCount.isVisible()) && !(await salesCount.inputValue())) {
        await salesCount.fill('3');
        await page.getByRole('button', { name: 'Save', exact: true }).click();
        await expect(page.getByText('Every department has a number')).toBeVisible();
      }
      await answer(page, `Here is a fair answer number ${i + 1} about how things work.`);
    }
    await expect(finished(page)).toBeVisible();

    await page.goto('/company/dashboard');
    await expect(page.getByText(/preparing your Stage 1 proposal/)).toBeVisible();
    await expect(page.getByText(/invite your team/i)).toHaveCount(0);
  });

  test("a manager's link opens their own conversation and nothing of the key user's", async ({ page }) => {
    await page.goto(`/leadership/${MANAGER_LINK}`);
    await expect(page.getByText('Before we start')).toBeVisible();
    await page.getByRole('button', { name: /let's start/ }).click();
    await expect(page.getByText(/Shall we start\?/)).toBeVisible();
    await expect(page.getByText(OWN_WORDS, { exact: false })).toHaveCount(0);
    await expect(page.getByText('Who takes part')).toHaveCount(0);
  });

  test('a link that is not valid says so', async ({ page }) => {
    await page.goto('/leadership/not-a-real-link');
    await expect(page.getByText(/expired or isn't valid/)).toBeVisible();
  });
});
