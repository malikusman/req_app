import { test, expect, type Page } from '@playwright/test';

// The report reader is the one surface here whose correctness is browser
// behaviour rather than a pure function: it drives a same-origin iframe, scales
// it to fit the stage, tracks which page is in view, and builds its jump rail by
// reading the report's own markup. A request spec can prove the endpoint serves
// the right HTML -- it cannot prove any of that works.
//
// Setup: `docker compose up`, then
//   docker compose exec rails bundle exec rake e2e:seed_report_reader

const EMAIL = process.env.E2E_EMAIL ?? 'reader-e2e@worktruth.test';
const PASSWORD = process.env.E2E_PASSWORD ?? 'ReaderE2E123!';

async function login(page: Page) {
  await page.goto('/company/login');
  // By role, not getByLabel: the password field's "Show password" toggle also
  // carries "password" in its accessible name.
  await page.getByRole('textbox', { name: 'Email' }).fill(EMAIL);
  await page.getByRole('textbox', { name: 'Password' }).fill(PASSWORD);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page).toHaveURL(/\/company\/(dashboard|onboarding)/);
}

async function openReader(page: Page) {
  await page.goto('/company/reports');
  await page.getByRole('button', { name: /read full report/i }).click();
  await expect(page).toHaveURL(/\/company\/reports\/\d+\/read\?variant=full/);
  // The rail only appears once the frame has loaded and been parsed.
  await expect(page.getByRole('navigation', { name: 'Report sections' }).getByRole('button').first()).toBeVisible();
}

/** "3 of 19" -> { current: 3, total: 19 } */
async function pageIndicator(page: Page) {
  const text = await page.locator('text=/^\\d+ of \\d+$/').first().innerText();
  const [current, total] = text.split(' of ').map((n) => Number(n.trim()));
  return { current, total };
}

async function frameScrollTop(page: Page) {
  return page.frameLocator('iframe[title="Report"]').locator('body').evaluate(
    (body) => (body.ownerDocument.scrollingElement ?? body).scrollTop
  );
}

test.describe('company report reader', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('the reports page leads with what the report found, not a filename', async ({ page }) => {
    await page.goto('/company/reports');

    // The expert-validated opportunity figure -- the number that previously
    // reached the dashboard and no PDF at all.
    await expect(page.getByText(/AED 450,000/)).toBeVisible();
    await expect(page.getByText(/Expert validated/i)).toBeVisible();
    // Honest page counts on the buttons, which is the whole reason the brief
    // gets clicked rather than guessed at.
    await expect(page.getByRole('button', { name: /read full report · \d+ pp/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /read executive brief · \d+ pp/i })).toBeVisible();
  });

  test('renders the report and reports a real page count', async ({ page }) => {
    await openReader(page);

    const { current, total } = await pageIndicator(page);
    expect(current).toBe(1);
    expect(total).toBeGreaterThan(5);

    // The page count in the chrome must match the pages actually in the frame.
    const pagesInFrame = await page
      .frameLocator('iframe[title="Report"]')
      .locator('section.page')
      .count();
    expect(pagesInFrame).toBe(total);
  });

  test('builds a jump rail of section names, not action titles', async ({ page }) => {
    await openReader(page);

    const rail = page.getByRole('navigation', { name: 'Report sections' });
    const labels = await rail.getByRole('button').allInnerTexts();

    // Section names come from .eyebrow. If this ever picks up <h1> instead, the
    // rail fills with sentences like "Core system dependency is the deepest
    // recurring friction, cited across 9 pieces of evidence".
    expect(labels).toContain('Executive summary');
    expect(labels).toContain('Recommendations');
    labels.forEach((label) => expect(label.length).toBeLessThan(60));

    // Fewer targets than pages: consecutive pages of one section collapse.
    const { total } = await pageIndicator(page);
    expect(labels.length).toBeLessThan(total);
    // And no target repeats.
    expect(new Set(labels).size).toBe(labels.length);
  });

  test('a consultant-authored section gets its own target under its real title', async ({ page }) => {
    await openReader(page);

    const rail = page.getByRole('navigation', { name: 'Report sections' });
    const labels = await rail.getByRole('button').allInnerTexts();

    // On .expert-page every eyebrow reads "Expert consultant", so the reader
    // falls back to the <h1>. Without that, every consultant section collapses
    // into one target labelled "Expert consultant".
    expect(labels).toContain('Risks and mitigations');
    expect(labels).not.toContain('Expert consultant');
  });

  test('clicking a section scrolls the document and updates the indicator', async ({ page }) => {
    await openReader(page);
    expect(await frameScrollTop(page)).toBe(0);

    await page.getByRole('navigation', { name: 'Report sections' })
      .getByRole('button', { name: 'Recommendations' })
      .click();

    await expect
      .poll(async () => (await pageIndicator(page)).current, { message: 'indicator follows the jump' })
      .toBeGreaterThan(1);
    expect(await frameScrollTop(page)).toBeGreaterThan(0);
  });

  test('marks the section containing the current page as active', async ({ page }) => {
    await openReader(page);
    const rail = page.getByRole('navigation', { name: 'Report sections' });

    await rail.getByRole('button', { name: 'Recommendations' }).click();

    // Active state is a range check (current >= this target, < the next one),
    // not equality, so a section's second page keeps its section highlighted.
    await expect(rail.getByRole('button', { name: 'Recommendations' })).toHaveClass(/border-accent/);
  });

  test('next and previous page buttons move one page at a time', async ({ page }) => {
    await openReader(page);

    await page.getByRole('button', { name: 'Next page' }).click();
    await expect.poll(async () => (await pageIndicator(page)).current).toBe(2);

    await page.getByRole('button', { name: 'Next page' }).click();
    await expect.poll(async () => (await pageIndicator(page)).current).toBe(3);

    await page.getByRole('button', { name: 'Previous page' }).click();
    await expect.poll(async () => (await pageIndicator(page)).current).toBe(2);
  });

  test('disables paging at the document boundaries', async ({ page }) => {
    await openReader(page);

    await expect(page.getByRole('button', { name: 'Previous page' })).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Next page' })).toBeEnabled();

    const { total } = await pageIndicator(page);
    for (let i = 1; i < total; i += 1) {
      await page.getByRole('button', { name: 'Next page' }).click();
    }

    await expect.poll(async () => (await pageIndicator(page)).current).toBe(total);
    await expect(page.getByRole('button', { name: 'Next page' })).toBeDisabled();
  });

  test('pages with the arrow keys', async ({ page }) => {
    await openReader(page);

    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => (await pageIndicator(page)).current).toBe(2);

    await page.keyboard.press('ArrowLeft');
    await expect.poll(async () => (await pageIndicator(page)).current).toBe(1);
  });

  test('scrolling the document by hand keeps the indicator honest', async ({ page }) => {
    await openReader(page);

    // Straight to the last page, bypassing the reader's own navigation, so this
    // exercises the IntersectionObserver rather than the click handler.
    const pages = page.frameLocator('iframe[title="Report"]').locator('section.page');
    await pages.last().scrollIntoViewIfNeeded();

    const { total } = await pageIndicator(page);
    await expect
      .poll(async () => (await pageIndicator(page)).current, { message: 'observer tracks manual scroll' })
      .toBeGreaterThan(total - 3);
  });

  test('fit page keeps the whole sheet on screen; fit width fills the stage', async ({ page }) => {
    await openReader(page);
    const frame = page.locator('iframe[title="Report"]');
    const rendered = async () => frame.evaluate((el) => el.getBoundingClientRect());

    // Fit page must show a whole sheet without the stage scrolling. Fit width
    // need not -- and on a LANDSCAPE page in a landscape stage the two often
    // coincide, because width is already the binding constraint. Asserting one
    // is strictly larger is only true for the portrait brief, tested below.
    const fitPage = await rendered();
    await page.getByRole('button', { name: 'Fit width' }).click();
    await expect.poll(async () => (await rendered()).width).toBeGreaterThanOrEqual(fitPage.width);

    await page.getByRole('button', { name: 'Fit whole page' }).click();
    await expect.poll(async () => (await rendered()).width).toBe(fitPage.width);
  });

  test('fit width is meaningfully larger than fit page for the portrait brief', async ({ page }) => {
    await openReader(page);
    await page.getByRole('button', { name: /executive brief/i }).click();
    await expect(page).toHaveURL(/variant=exec_brief/);
    await expect(page.getByRole('navigation', { name: 'Report sections' }).getByRole('button').first()).toBeVisible();

    const frame = page.locator('iframe[title="Report"]');
    const width = async () => frame.evaluate((el) => el.getBoundingClientRect().width);

    // A tall portrait page in a wide stage is height-bound at fit-page, so
    // fit-width is where the control earns its place.
    const fitPage = await width();
    await page.getByRole('button', { name: 'Fit width' }).click();
    await expect.poll(width).toBeGreaterThan(fitPage);
  });

  test('switching to the brief loads the other rendering', async ({ page }) => {
    await openReader(page);
    const full = await pageIndicator(page);

    await page.getByRole('button', { name: /executive brief/i }).click();

    await expect(page).toHaveURL(/variant=exec_brief/);
    await expect.poll(async () => (await pageIndicator(page)).total).toBeLessThan(full.total);

    // The brief is portrait, so the frame is taller than it is wide -- proof the
    // reader picked up the other paper geometry rather than reusing landscape.
    const box = await page.locator('iframe[title="Report"]').boundingBox();
    expect(box!.height).toBeGreaterThan(box!.width);

    // And its own sections, not the full report's.
    const labels = await page
      .getByRole('navigation', { name: 'Report sections' })
      .getByRole('button')
      .allInnerTexts();
    expect(labels).toContain('The answer');
    expect(labels).not.toContain('Methodology');
  });

  test('both renderings quote the same governing thought', async ({ page }) => {
    await openReader(page);
    const readFirstPageHeadline = async () =>
      page
        .frameLocator('iframe[title="Report"]')
        .locator('section.page')
        .first()
        .innerText();

    const fullText = await readFirstPageHeadline();

    await page.getByRole('button', { name: /executive brief/i }).click();
    await expect(page).toHaveURL(/variant=exec_brief/);
    await expect(page.getByRole('navigation', { name: 'Report sections' }).getByRole('button').first()).toBeVisible();

    // One snapshot, two projections. The company name is the cheapest thing both
    // must agree on; a mismatch means they are not rendering the same report.
    const briefText = await readFirstPageHeadline();
    expect(briefText).toContain('Reader E2E Co');
    expect(fullText).toContain('Reader E2E Co');
  });

  test('escape returns to the reports list', async ({ page }) => {
    await openReader(page);

    await page.keyboard.press('Escape');

    await expect(page).toHaveURL(/\/company\/reports$/);
  });

  test('the reader is reachable by direct link, not only by clicking through', async ({ page }) => {
    await openReader(page);
    const url = page.url();

    await page.goto('/company/dashboard');
    await page.goto(url);

    await expect(page.getByRole('navigation', { name: 'Report sections' }).getByRole('button').first()).toBeVisible();
    expect((await pageIndicator(page)).total).toBeGreaterThan(5);
  });
});
