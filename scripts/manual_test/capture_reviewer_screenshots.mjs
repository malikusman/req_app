import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const FRONTEND_URL = process.env.FRONTEND_URL || 'http://localhost:5173';
const API_URL = process.env.API_URL || 'http://localhost:3000';
const OUTPUT_DIR =
  process.env.OUTPUT_DIR || '/Users/usmanmalik/Documents/projects/req_app/docs/reviewer-screenshots';

async function login() {
  const response = await fetch(`${API_URL}/api/v1/auth/reviewer/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'reviewer@reqapp.local', password: 'password123' }),
  });

  if (!response.ok) {
    throw new Error(`Reviewer login failed: ${response.status} ${response.statusText}`);
  }

  return response.json();
}

async function authenticatedContext(session, options = {}) {
  const context = await browser.newContext(options);
  await context.addInitScript((payload) => {
    localStorage.setItem('req_app_session', JSON.stringify(payload));
  }, session);
  return context;
}

async function waitForApp(page, text) {
  await page.waitForLoadState('networkidle');
  if (text) {
    await page.getByText(text, { exact: false }).first().waitFor({ timeout: 15000 });
  }
}

async function capture(page, route, filename, text) {
  await page.goto(`${FRONTEND_URL}${route}`, { waitUntil: 'domcontentloaded' });
  await waitForApp(page, text);
  await page.screenshot({ path: `${OUTPUT_DIR}/${filename}`, fullPage: true });
}

const { token, user } = await login();
const session = { portal: 'reviewer', token, user };

await mkdir(OUTPUT_DIR, { recursive: true });

const browser = await chromium.launch({ headless: true });

try {
  const desktop = await authenticatedContext(session, {
    viewport: { width: 1440, height: 1200 },
    deviceScaleFactor: 1,
  });
  const page = await desktop.newPage();

  await capture(page, '/reviewer/dashboard', 'dashboard.png', 'Assigned companies');
  await capture(page, '/reviewer/companies/1', 'company-overview-acme.png', 'Quick actions');
  await capture(page, '/reviewer/inbox', 'inbox.png', 'Follow-ups');
  await capture(page, '/reviewer/companies/1/conversations', 'conversations-acme.png', 'Conversations');
  await capture(page, '/reviewer/companies/1/reports/1/review?step=context', 'workspace-context.png', 'Engagement overview');
  await capture(page, '/reviewer/companies/1/reports/1/review?step=evidence', 'workspace-evidence.png', 'Source evidence');
  await capture(page, '/reviewer/companies/1/reports/1/review?step=synthesis', 'workspace-synthesis.png', 'Agent synthesis');
  await capture(page, '/reviewer/companies/1/reports/1/review?step=sections', 'workspace-sections.png', 'Validate deliverable');
  await capture(page, '/reviewer/companies/1/reports/1/review?step=collaborate', 'workspace-collaborate-solo.png', 'Collaborate');
  await capture(page, '/reviewer/companies/1/reports/1/review?step=submit', 'workspace-submit.png', 'Submit checklist');

  await page.getByRole('button', { name: 'Submit review' }).last().click();
  await page.getByText('Submit your review?', { exact: false }).waitFor({ timeout: 15000 });
  await page.screenshot({ path: `${OUTPUT_DIR}/workspace-submit-dialog.png`, fullPage: true });

  await desktop.close();

  const mobile = await authenticatedContext(session, {
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
    deviceScaleFactor: 2,
  });
  const mobilePage = await mobile.newPage();
  await capture(
    mobilePage,
    '/reviewer/companies/1/reports/1/review?step=sections',
    'workspace-sections-mobile.png',
    'Validate deliverable'
  );
  await mobile.close();
} finally {
  await browser.close();
}
