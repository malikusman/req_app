import { expect, test, type Page } from '@playwright/test';
import type { PlanContent, PlanDetail } from '../src/lib/deepDivePlan';

const route = '/consultant/companies/1/deep-dive-plans/2';
const root = '**/api/v1/consultant/companies/1/task_intelligence_runs/2/deep_dive_plans';
const task = 'proposal-10';
const otherTask = 'proposal-11';
const original: PlanContent = {
  objective: 'Confirm how invoices are matched', scope: 'Invoice processing', instructions: 'Verify before drawing conclusions.',
  duration_minutes: 35, focus_areas: ['Handoff'], document_requests: ['An anonymized invoice'],
  sections: [{ title: 'Process and exceptions', questions: [
    { text: 'What triggers this work?', source_ids: [19], clarification_ids: [] },
    { text: 'Which steps are performed separately?', source_ids: [], clarification_ids: [7] },
  ] }],
};
const context = {
  selection_version: 10, cluster_revision_ids: [10], gaps: ['Overlap is unresolved.'],
  participants: [{ id: 33, display_name: 'Adam', role_title: 'Accounts clerk', eligible: true, discovery_consent_recorded: true }],
  sources: [{ id: 19, name: 'Invoice processing', version: 1, employee_id: 33, conversation_id: 32, facts: [], effort_observations: [] }],
  open_clarifications: [{ id: 7, source_ids: [19, 31], missing_evidence: ['Compare the handoffs.'], why_it_matters: ['Avoid counting shared work twice.'] }],
  relationships: [], relationship_judgments: [], effort: {},
};

async function mockPlans(page: Page, { unavailable = false, draft = false, rejectFirstSave = false } = {}) {
  const versions = new Map<number, PlanContent>();
  const plan: PlanDetail = { task_id: task, title: 'Invoice processing', status: 'not_started', retry_available: false,
    version: null, latest_version: null, approved_version: null, context: null, content: null, generation_error: null, history: [] };
  let generationRequests = 0;

  function append(content: PlanContent, action: string, reason: string) {
    const version = (plan.version ?? 0) + 1;
    versions.set(version, content);
    Object.assign(plan, { content, version, latest_version: version, status: action === 'approved' ? 'approved' : 'draft' });
    if (action === 'approved') plan.approved_version = version;
    plan.history.unshift({ version, action, reason, consultant_user_id: 12, created_at: '2026-11-12T00:00:00Z' });
  }

  if (draft) {
    plan.context = context;
    append(structuredClone(original), 'generated', 'Requested AI interview plan.');
  }
  const otherPlan = { ...plan, task_id: otherTask, title: 'Expense tracking', status: 'not_started',
    version: null, latest_version: null, context: null, content: null, history: [] };

  await page.addInitScript(() => localStorage.setItem('req_app_session', JSON.stringify({
    portal: 'consultant', token: 'test-token', user: { id: 12, name: 'Consultant', email: 'consultant@example.test' },
  })));
  await page.route('**/api/v1/consultant/**', route => route.fulfill({ status: 503, json: {} }));
  await page.route(root, route => route.fulfill({ json: { selection_version: 10, tasks: [
    { task_id: task, title: plan.title, status: plan.status, retry_available: plan.retry_available },
    { task_id: otherTask, title: otherPlan.title, status: otherPlan.status, retry_available: false },
  ] } }));
  await page.route(`${root}/${otherTask}`, route => route.fulfill({ json: otherPlan }));
  await page.route(new RegExp(`/deep_dive_plans/${task}(?:[/?].*)?$`), async route => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname.endsWith('/generate')) {
      generationRequests += 1;
      plan.context = context;
      if (unavailable && generationRequests === 1) {
        Object.assign(plan, { status: 'failed', retry_available: true, generation_error: 'AI generation is unavailable or failed.' });
      } else {
        Object.assign(plan, { status: 'queued', retry_available: false, generation_error: null });
        await route.fulfill({ json: plan });
        append(structuredClone(original), 'generated', 'Requested AI interview plan.');
        return;
      }
    } else if (request.method() === 'PATCH' || url.pathname.endsWith('/approve')) {
      if (request.method() === 'PATCH' && rejectFirstSave) {
        rejectFirstSave = false;
        await route.fulfill({ status: 422, json: { error: 'Plan could not be saved.' } });
        return;
      }
      const body = request.postDataJSON() as { expected_version: number; reason: string; content?: PlanContent };
      expect(body.expected_version).toEqual(plan.version);
      append(body.content ?? plan.content!, body.content ? 'edited' : 'approved', body.reason);
    }
    const historical = Number(url.searchParams.get('version'));
    await route.fulfill({ json: historical ? { ...plan, version: historical, content: versions.get(historical) } : plan });
  });
  await page.goto(route);
}

test('generates, edits and approves a versioned plan, then reloads and inspects history', async ({ page }) => {
  await mockPlans(page);
  await page.getByRole('button', { name: 'Generate AI draft' }).click();
  await expect(page.getByRole('heading', { name: 'Interview plan', exact: true })).toBeVisible();
  await expect(page.getByText('Open clarification #7', { exact: true })).toBeVisible();
  const section = page.getByRole('group', { name: 'Process and exceptions' });
  await section.getByRole('button', { name: 'Move question 2 up' }).click();
  await expect(section.getByRole('textbox', { name: 'Question 1' })).toHaveValue('Which steps are performed separately?');
  await section.getByRole('textbox', { name: 'Question 2' }).fill('Who triggers this work?');
  await section.getByRole('button', { name: 'Add question' }).click();
  await section.getByRole('textbox', { name: 'Question 3' }).fill('Where is the exception recorded?');
  await section.getByRole('button', { name: 'Remove question' }).nth(1).click();
  await page.getByRole('textbox', { name: 'Scope', exact: true }).fill('Invoice processing and exceptions');
  await page.getByRole('textbox', { name: 'Decision reason' }).fill('Cover the exception handoff');
  await page.getByRole('button', { name: 'Save new version' }).click();
  await expect(page.getByText('Plan version 2', { exact: true })).toBeVisible();
  await page.getByRole('textbox', { name: 'Decision reason' }).fill('Reviewed against the evidence');
  await page.getByRole('button', { name: 'Approve plan' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Confirm approval' }).click();
  await expect(page.getByText('Plan version 3 · approved version 3')).toBeVisible();
  await page.reload();
  await expect(page.getByRole('textbox', { name: 'Scope', exact: true })).toHaveValue('Invoice processing and exceptions');
  await expect(page.getByRole('textbox', { name: 'Scope', exact: true })).toBeDisabled();
  await page.getByLabel('Plan version').selectOption('1');
  await expect(page.getByRole('textbox', { name: 'Scope', exact: true })).toHaveValue('Invoice processing');
  await expect(page.getByText('Historical version', { exact: true })).toBeVisible();
  await expect(page.getByText('Latest plan (version 3): Approved', { exact: true })).toBeVisible();
});

test('shows a model failure and lets the consultant retry', async ({ page }) => {
  await mockPlans(page, { unavailable: true });
  await page.getByRole('button', { name: 'Generate AI draft' }).click();
  await expect(page.getByRole('alert')).toHaveText('AI generation is unavailable or failed.');
  await expect(page.getByRole('heading', { name: 'Interview plan', exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Retry generation' }).click();
  await expect(page.getByRole('heading', { name: 'Interview plan', exact: true })).toBeVisible();
});

test('keeps dirty edits through a version change, a failed save, and a task switch attempt', async ({ page }) => {
  await mockPlans(page, { draft: true, rejectFirstSave: true });
  const scope = page.getByRole('textbox', { name: 'Scope', exact: true });
  const history = page.getByLabel('Plan version');
  const dialog = page.getByRole('dialog', { name: 'Discard unsaved plan edits?' });
  const other = page.getByRole('navigation', { name: 'Selected tasks' }).getByRole('button', { name: /Expense tracking/ });

  await scope.fill('Invoice processing and exceptions');
  await history.selectOption('1');
  await dialog.getByRole('button', { name: 'Stay' }).click();
  await expect(history).toHaveValue('');
  await expect(scope).toHaveValue('Invoice processing and exceptions');

  await page.getByRole('textbox', { name: 'Decision reason' }).fill('Cover exception handling');
  await page.getByRole('button', { name: 'Save new version' }).click();
  await expect(page.getByRole('alert')).toBeVisible();
  await other.click();
  await dialog.getByRole('button', { name: 'Stay' }).click();
  await expect(scope).toHaveValue('Invoice processing and exceptions');

  await page.getByRole('button', { name: 'Save new version' }).click();
  await expect(page.getByText('Plan version 2', { exact: true })).toBeVisible();
  await other.click();
  await expect(page.getByRole('heading', { name: 'Expense tracking' })).toBeVisible();
  await expect(dialog).toHaveCount(0);

  await page.getByRole('navigation', { name: 'Selected tasks' }).getByRole('button', { name: /Invoice processing/ }).click();
  await expect(scope).toHaveValue('Invoice processing and exceptions');
  await scope.fill('Unsaved third version');
  await history.selectOption('1');
  await dialog.getByRole('button', { name: 'Discard' }).click();
  await expect(scope).toHaveValue(original.scope);
  await expect(scope).toBeDisabled();
});

test('guards mobile task switching, browser Back and the Task selection link', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await mockPlans(page, { draft: true });
  const switcher = page.getByLabel('Selected task', { exact: true });
  const scope = page.getByRole('textbox', { name: 'Scope', exact: true });
  const dialog = page.getByRole('dialog', { name: 'Discard unsaved plan edits?' });

  await expect(page.getByRole('navigation', { name: 'Selected tasks' })).toBeHidden();
  await scope.fill('Unsaved scope');
  await switcher.selectOption(otherTask);
  await dialog.getByRole('button', { name: 'Discard' }).click();
  await expect(page.getByRole('heading', { name: 'Expense tracking' })).toBeVisible();
  await switcher.selectOption(task);
  await expect(scope).toHaveValue(original.scope);

  await scope.fill('Another unsaved change');
  await page.evaluate(() => window.history.back());
  await dialog.getByRole('button', { name: 'Stay' }).click();
  await expect(scope).toHaveValue('Another unsaved change');
  await page.getByRole('link', { name: 'Task selection', exact: true }).click();
  await dialog.getByRole('button', { name: 'Discard' }).click();
  await expect(page).toHaveURL(/\/task-selection\?run=2$/);
});

test('warns before reloading a plan with unsaved edits', async ({ page }) => {
  await mockPlans(page, { draft: true });
  const scope = page.getByRole('textbox', { name: 'Scope', exact: true });
  await scope.click();
  await scope.fill('Keep this edit');
  const prompt = page.waitForEvent('dialog').then(async dialog => {
    await dialog.dismiss();
    expect(dialog.type()).toBe('beforeunload');
  });
  await Promise.all([page.evaluate(() => { window.location.reload(); }), prompt]);
  await expect(scope).toHaveValue('Keep this edit');
});

test('only clears the consultant session when discarding edits to log out', async ({ page }) => {
  await mockPlans(page, { draft: true });
  const scope = page.getByRole('textbox', { name: 'Scope', exact: true });
  const logout = page.getByRole('button', { name: 'Log out' });
  const dialog = page.getByRole('dialog', { name: 'Discard unsaved plan edits?' });
  await scope.fill('Keep my plan changes');
  await logout.click();
  await dialog.getByRole('button', { name: 'Stay' }).click();
  await expect(scope).toHaveValue('Keep my plan changes');
  await logout.click();
  await dialog.getByRole('button', { name: 'Discard' }).click();
  await expect(page).toHaveURL(/\/consultant\/login$/);
  await expect.poll(() => page.evaluate(() => localStorage.getItem('req_app_session'))).toBeNull();
});
