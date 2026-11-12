import { expect, test, type Page } from '@playwright/test';
import type { ReviewCommand, ReviewTask, SelectionReview } from '../src/lib/taskSelection';

const companyPath = '/consultant/companies/1/task-selection';
const run = { id: 9, version: 2, evaluation_mode: 'deterministic' };
const makeTask = (id: string, title: string, source_ids: number[], proposal_ids: number[] = []): ReviewTask => ({
  id, title, source_ids, proposal_ids, status: 'pending', origin_task_ids: [], notes: [], participant_ids: [],
  gaps: ['Unresolved overlap remains.'], effective_effort: { status: 'withheld_possible_overlap' }, effort_assumptions: {},
});
const tasks = [makeTask('proposal-1', 'Invoice matching', [10, 30], [1]), makeTask('proposal-2', 'Invoice exception handling', [20], [2])];
tasks[1].effective_effort = { status: 'unknown_active_effort' };

async function mockReview(page: Page, failParticipantSave = false) {
  const commands: (ReviewCommand & { expected_version: number; reason?: string })[] = [];
  const review: SelectionReview = {
    run, version: 0, latest_version: 0, status: 'draft', latest_status: 'draft', history: [],
    snapshot: { tasks: structuredClone(tasks), selected_order: [], relationship_overrides: {},
      sampling: { planned_interviews: 0, available_slots: null, gaps: ['Interview capacity has not been recorded.'] } },
    proposals: tasks.map((task, index) => ({
      id: index + 1, title: task.title, rank: index === 0 ? 1 : null, score: 10 - index, priority: 'medium', confidence: 'low',
      disposition: index === 0 ? 'shortlisted' : 'deferred_overlap', disposition_reason: 'Validate workload boundaries.',
      process_cluster_revision_number: 2, source_ids: task.source_ids,
      assessment: { risks: ['Manual reconciliation'], unknowns: ['Process boundary'], deep_dive_objectives: ['Confirm handoff'],
        evidence_sources: [], potential_overlap_cluster_ids: [11] },
    })),
    sources: tasks.flatMap((task, index) => task.source_ids.map(id => ({
      id, name: task.title, employee_id: index + 1, conversation_id: id + 40, version: 1, effort_observations: [],
    }))),
    relationships: [{ source_ids: [10, 20], classification: 'UNRESOLVED', rationale: 'Similar steps with insufficient boundaries.',
      clarification_request: { id: 19, status: 'open', missing_evidence: ['Which output closes each activity?'],
        why_it_matters: ['Avoid counting effort twice.'], unknowns: ['One process or two?'] } }],
    eligible_participants: [
      { id: 1, name: 'Adam', discovery_consent_recorded: true },
      { id: 2, name: 'Sam', discovery_consent_recorded: false },
    ],
  };
  const initial = structuredClone(review);
  await page.addInitScript(() => localStorage.setItem('req_app_session', JSON.stringify({
    portal: 'consultant', token: 'test-token', user: { id: 12, name: 'Consultant', email: 'consultant@example.test' },
  })));
  await page.route('**/api/v1/consultant/dashboard', route => route.fulfill({ status: 503, json: {} }));
  await page.route('**/task_intelligence_runs', route => route.fulfill({ json: { task_intelligence_runs: [run], next_before_id: null } }));
  await page.route('**/selection_review*', route => route.fulfill({
    json: route.request().url().includes('version=0') ? { ...initial, latest_version: review.version, history: review.history } : review,
  }));
  await page.route('**/selection_review/commands', async route => {
    const command = route.request().postDataJSON() as typeof commands[number];
    commands.push(command);
    if (command.action === 'participants' && failParticipantSave) {
      await route.fulfill({ status: 422, json: { error: 'Choose eligible employees with Discovery evidence linked to this task.' } });
      return;
    }
    const snapshot = review.snapshot;
    const task = snapshot.tasks.find(row => row.id === command.task_id);
    switch (command.action) {
      case 'select':
        task!.status = 'selected';
        task!.decision_reason = command.reason;
        snapshot.selected_order.push(task!.id);
        break;
      case 'reject':
      case 'defer':
        task!.status = command.action === 'reject' ? 'rejected' : 'deferred';
        task!.decision_reason = command.reason;
        snapshot.selected_order = snapshot.selected_order.filter(id => id !== task!.id);
        break;
      case 'participants':
        task!.participant_ids = command.participant_ids!;
        snapshot.sampling.planned_interviews = command.participant_ids!.length;
        break;
      case 'reorder':
        snapshot.selected_order = command.task_ids!;
        break;
      case 'merge':
        snapshot.tasks.filter(row => command.task_ids?.includes(row.id)).forEach(row => { row.status = 'merged'; });
        snapshot.tasks.push(makeTask('merged', command.title!, [10, 30, 20], [1, 2]));
        break;
      case 'split':
        task!.status = 'split';
        command.children!.forEach((child, index) => snapshot.tasks.push(makeTask(`part-${index}`, child.title, child.source_ids, [1, 2])));
        break;
      case 'finalize':
        review.status = review.latest_status = 'finalized';
        snapshot.final_selection = { provisional: true };
        break;
    }
    review.latest_version = ++review.version;
    review.history.unshift({ version: review.version, action: command.action, reason: command.reason ?? 'Updated interview participants.', status: review.status,
      consultant_user_id: 12, created_at: '2026-11-12T00:00:00Z' });
    await route.fulfill({ json: review });
  });
  await page.goto(companyPath);
  await expect(page.getByRole('main').getByRole('heading', { name: 'Deep Dive Task Selection', exact: true })).toBeVisible();
  return commands;
}

function card(page: Page, title: string) {
  return page.getByRole('article', { name: title, exact: true });
}

function detail(page: Page, title: string) {
  return page.getByRole('dialog', { name: title, exact: true });
}

async function closePanel(panel: ReturnType<Page['getByRole']>) {
  await panel.getByRole('button', { name: 'Close', exact: true }).click();
  await expect(panel).toBeHidden();
}

async function decide(page: Page, reason: string, confirmation = 'Save decision') {
  const dialog = page.getByRole('dialog').filter({ has: page.getByRole('button', { name: confirmation, exact: true }) });
  await dialog.getByRole('textbox', { name: 'Reason', exact: true }).fill(reason);
  await dialog.getByRole('button', { name: confirmation, exact: true }).click();
  await expect(dialog).toBeHidden();
}

test('filters tasks and moves a selection out of Pending into Selected for Deep Dive', async ({ page }) => {
  await mockReview(page);
  const task = card(page, 'Invoice matching');
  const pending = page.getByRole('region', { name: 'Pending review', exact: true });
  const selected = page.getByRole('region', { name: 'Selected for Deep Dive', exact: true });
  const filters = page.getByRole('tablist', { name: 'Filter tasks' });
  await expect(pending.getByRole('article', { name: 'Invoice matching' })).toBeVisible();
  await expect(card(page, 'Invoice exception handling').getByText('Time estimate not yet confirmed')).toBeVisible();
  await filters.getByRole('tab', { name: 'Selected', exact: true }).click();
  await expect(page.getByText('No tasks have been selected for Deep Dive yet.')).toBeVisible();
  await filters.getByRole('tab', { name: 'Pending', exact: true }).click();
  await task.getByRole('button', { name: 'Select', exact: true }).click();
  await decide(page, 'Validate invoice matching');
  await expect(task).toHaveCount(0);
  await filters.getByRole('tab', { name: 'All', exact: true }).click();
  await expect(selected.getByRole('article', { name: 'Invoice matching' })).toBeVisible();
  await expect(pending.getByRole('article', { name: 'Invoice matching' })).toHaveCount(0);
  await expect(task).toHaveCount(1);
  await filters.getByRole('tab', { name: 'Selected', exact: true }).click();
  await expect(task.getByText('Selected', { exact: true })).toBeVisible();
  await expect(card(page, 'Invoice exception handling')).toHaveCount(0);
  await filters.getByRole('tab', { name: 'Other Decisions', exact: true }).click();
  await expect(page.getByText('Rejected and deferred tasks will appear here.')).toBeVisible();
  await filters.getByRole('tab', { name: 'Pending', exact: true }).click();
  const other = card(page, 'Invoice exception handling');
  await other.getByRole('button', { name: 'Reject', exact: true }).click();
  await decide(page, 'Outside this investigation');
  await expect(other).toHaveCount(0);
  await filters.getByRole('tab', { name: 'Other Decisions', exact: true }).click();
  await expect(other.getByText('Rejected', { exact: true })).toBeVisible();
  await other.getByRole('button', { name: 'Details' }).click();
  const panel = detail(page, 'Invoice exception handling');
  await expect(panel.getByText('Outside this investigation')).toBeVisible();
  await panel.getByRole('button', { name: 'Defer', exact: true }).click();
  await decide(page, 'Revisit after the next review');
  await closePanel(panel);
  await expect(other.getByText('Deferred', { exact: true })).toBeVisible();
});

test('keeps clarifications in details and persists a linked participant through refresh', async ({ page }) => {
  const commands = await mockReview(page);
  const task = card(page, 'Invoice matching');
  const other = card(page, 'Invoice exception handling');
  await expect(task.getByText('Needs clarification', { exact: true })).toBeVisible();
  await expect(page.getByText('Which output closes each activity?')).toBeHidden();
  await other.getByRole('button', { name: 'Details' }).click();
  const evidence = detail(page, 'Invoice exception handling');
  await evidence.getByText('Outside shortlist · Invoice exception handling').click();
  await expect(evidence.getByText(/deferred overlap · medium priority/)).toBeVisible();
  await evidence.getByText('Clarification · Possible overlap').click();
  await expect(evidence.getByText('Which output closes each activity?')).toBeVisible();
  await expect(evidence.getByText('Avoid counting effort twice.')).toBeVisible();
  await closePanel(evidence);
  await task.getByRole('button', { name: 'Select', exact: true }).click();
  await decide(page, 'Validate the overlap first');
  await task.getByRole('button', { name: 'Choose participants' }).click();
  const picker = detail(page, 'Invoice matching');
  await expect(picker.getByRole('checkbox', { name: /Sam/ })).toHaveCount(0);
  await picker.getByRole('checkbox', { name: 'Adam' }).check();
  await picker.getByRole('button', { name: 'Save participants' }).click();
  await expect(picker.getByRole('status')).toHaveText('Participants saved.');
  expect(commands[1]).toMatchObject({ action: 'participants', participant_ids: [1], expected_version: 1 });
  expect(commands[1]).not.toHaveProperty('reason');
  await page.reload();
  await expect(task.getByText(/Participants · Adam/)).toBeVisible();
  await task.getByRole('button', { name: 'Choose participants' }).click();
  await expect(picker.getByRole('checkbox', { name: 'Adam' })).toBeChecked();
  await closePanel(picker);
  await page.getByRole('button', { name: 'Finalize selection' }).click();
  await expect(page.getByRole('dialog', { name: 'Finalize selection' }).getByText(/Finalizing locks this review/)).toBeVisible();
  await decide(page, 'Proceed with gaps documented', 'Confirm finalization');
  await expect(page.getByText('Finalized with unresolved gaps', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Finalize selection' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Review history' }).click();
  const history = detail(page, 'Review history');
  await expect(history.getByText('Updated interview participants.')).toBeVisible();
  await history.getByLabel('Review revision').selectOption('0');
  await closePanel(history);
  await expect(page.getByText('Read-only revision', { exact: true })).toBeVisible();
  await expect(task.getByText('Pending', { exact: true })).toBeVisible();
});

test('uses merged source lineage and splits from the Decisions panel', async ({ page }) => {
  const commands = await mockReview(page);
  for (const title of tasks.map(task => task.title)) {
    await card(page, title).getByRole('button', { name: 'Details' }).click();
    const panel = detail(page, title);
    await panel.getByRole('tab', { name: 'Decisions', exact: true }).click();
    await panel.getByRole('checkbox', { name: 'Mark for merge' }).check();
    await closePanel(panel);
  }
  await page.getByText('Manage task scopes · 2 marked for merge', { exact: true }).click();
  await page.getByText('Merge marked tasks (2)', { exact: true }).click();
  await page.getByLabel('Merged task title').fill('Invoice workflow');
  await page.getByRole('button', { name: 'Merge marked tasks', exact: true }).click();
  await decide(page, 'Compare linked scopes');
  await card(page, 'Invoice workflow').getByRole('button', { name: 'Details' }).click();
  const panel = detail(page, 'Invoice workflow');
  await panel.getByRole('tab', { name: 'Participants', exact: true }).click();
  await expect(panel.getByRole('checkbox', { name: 'Adam' })).toHaveCount(1);
  await expect(panel.getByRole('checkbox', { name: /Sam/ })).toBeVisible();
  await expect(panel.getByText('Discovery consent unrecorded')).toBeVisible();
  await panel.getByRole('tab', { name: 'Decisions', exact: true }).click();
  await panel.getByText('Split task', { exact: true }).click();
  await panel.getByLabel('Child 1 title').fill('Validate invoice');
  await panel.getByLabel('Child 2 title').fill('Triage exceptions');
  await panel.locator('input[name="sources0"][value="10"]').check();
  await panel.locator('input[name="sources0"][value="30"]').check();
  await panel.locator('input[name="sources1"][value="20"]').check();
  await panel.getByRole('button', { name: 'Save split' }).click();
  await decide(page, 'Different investigation objectives');
  await expect(card(page, 'Triage exceptions')).toBeVisible();
  expect(commands[0].task_ids).toEqual(['proposal-1', 'proposal-2']);
  expect(commands[1].children).toEqual([{ title: 'Validate invoice', source_ids: [10, 30] }, { title: 'Triage exceptions', source_ids: [20] }]);
});

test('preserves the selected task order across filters and reload', async ({ page }) => {
  await mockReview(page);
  for (const title of tasks.map(task => task.title)) {
    await card(page, title).getByRole('button', { name: 'Select', exact: true }).click();
    await decide(page, `Investigate ${title}`);
  }
  const selected = page.getByRole('region', { name: 'Selected for Deep Dive', exact: true });
  const titles = selected.getByRole('heading', { level: 3 });
  await expect(titles).toHaveText(['Invoice matching', 'Invoice exception handling']);
  await selected.getByRole('button', { name: 'Move Invoice exception handling up' }).click();
  await decide(page, 'Investigate exceptions first');
  await page.getByRole('tab', { name: 'Selected', exact: true }).click();
  await expect(titles).toHaveText(['Invoice exception handling', 'Invoice matching']);
  await page.reload();
  await expect(titles).toHaveText(['Invoice exception handling', 'Invoice matching']);
});

test('shows a participant save error beside the picker on mobile', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await mockReview(page, true);
  const task = card(page, 'Invoice matching');
  await task.getByRole('button', { name: 'Select', exact: true }).click();
  await decide(page, 'Investigate invoice matching');
  await task.getByRole('button', { name: 'Choose participants' }).click();
  const picker = detail(page, 'Invoice matching');
  await picker.getByRole('checkbox', { name: 'Adam' }).check();
  await picker.getByRole('button', { name: 'Save participants' }).click();
  await expect(picker.getByRole('alert')).toHaveText('Choose eligible employees with Discovery evidence linked to this task.');
  await expect(picker.getByRole('checkbox', { name: 'Adam' })).toBeChecked();
  await closePanel(picker);
  await expect(task.getByText('No participants assigned')).toBeVisible();
});
