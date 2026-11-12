import { expect, test, type Page } from '@playwright/test';
import type { ReviewCommand, ReviewTask, SelectionReview } from '../src/lib/taskSelection';

const companyPath = '/consultant/companies/1/task-selection';
const run = { id: 9, version: 2, evaluation_mode: 'deterministic' };
const makeTask = (id: string, title: string, source_ids: number[], proposal_ids: number[] = []): ReviewTask => ({
  id, title, source_ids, proposal_ids, status: 'pending', origin_task_ids: [], notes: [], participant_ids: [],
  gaps: ['Unresolved overlap remains.'], effective_effort: { status: 'withheld_possible_overlap' }, effort_assumptions: {},
});
const tasks = [makeTask('proposal-1', 'Invoice matching', [10], [1]), makeTask('proposal-2', 'Invoice exception handling', [20], [2])];

async function mockReview(page: Page) {
  const commands: (ReviewCommand & { expected_version: number; reason: string })[] = [];
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
    sources: tasks.map((task, index) => ({
      id: task.source_ids[0], name: task.title, employee_id: index + 1, conversation_id: index + 40, version: 1, effort_observations: [],
    })),
    relationships: [{ source_ids: [10, 20], classification: 'UNRESOLVED', rationale: 'Similar steps with insufficient boundaries.',
      clarification_request: { id: 19, status: 'open', missing_evidence: ['Which output closes each activity?'],
        why_it_matters: ['Avoid counting effort twice.'], unknowns: ['One process or two?'] } }],
    eligible_participants: [{ id: 1, name: 'Adam', discovery_consent_recorded: true }],
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
    const snapshot = review.snapshot;
    const task = snapshot.tasks.find(row => row.id === command.task_id);
    switch (command.action) {
      case 'select':
        task!.status = 'selected';
        snapshot.selected_order.push(task!.id);
        break;
      case 'participants':
        task!.participant_ids = command.participant_ids!;
        snapshot.sampling.planned_interviews = command.participant_ids!.length;
        break;
      case 'merge':
        snapshot.tasks.filter(row => command.task_ids?.includes(row.id)).forEach(row => { row.status = 'merged'; });
        snapshot.tasks.push(makeTask('merged', command.title!, [10, 20], [1, 2]));
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
    review.history.unshift({ version: review.version, action: command.action, reason: command.reason, status: review.status,
      consultant_user_id: 12, created_at: '2026-11-12T00:00:00Z' });
    await route.fulfill({ json: review });
  });
  await page.goto(companyPath);
  await expect(page.getByRole('main').getByRole('heading', { name: 'Task selection', exact: true })).toBeVisible();
  return commands;
}

test('shows proposals, uncertainty and reasons, then saves participants and provisional selection', async ({ page }) => {
  const commands = await mockReview(page);
  await page.getByText('Outside shortlist · Invoice exception handling').click();
  await expect(page.getByText(/deferred overlap · medium priority/)).toBeVisible();
  await expect(page.getByText('Clarification #19 · open')).toBeVisible();
  await expect(page.getByText('Which output closes each activity?')).toBeVisible();
  await expect(page.getByText('Avoid counting effort twice.')).toBeVisible();
  const task = page.getByRole('region', { name: 'Invoice matching', exact: true });
  await task.getByRole('button', { name: 'Select', exact: true }).click();
  await expect(page.getByRole('alert')).toHaveText('Enter a reason for this decision.');
  const reason = page.getByLabel('Reason for next decision');
  await reason.fill('Validate the overlap first');
  await task.getByRole('button', { name: 'Select', exact: true }).click();
  await expect(task.getByRole('heading', { level: 3 })).toHaveText('Invoice matching · selected');
  await task.getByText('Choose participants').click();
  await task.getByRole('checkbox', { name: /Adam #1 · linked evidence/ }).check();
  await reason.fill('Adam has linked evidence');
  await task.getByRole('button', { name: 'Save participants' }).click();
  await expect(task.getByText('Participants · Adam #1')).toBeVisible();
  await reason.fill('Proceed with gaps documented');
  await page.getByRole('button', { name: 'Finalize selection' }).click();
  await expect(page.getByText(/Finalized with unresolved gaps · review v3/)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Finalize selection' })).toHaveCount(0);
  expect(commands.map(command => [command.action, command.expected_version])).toEqual([['select', 0], ['participants', 1], ['finalize', 2]]);
  await page.getByLabel('Review revision').selectOption('0');
  await expect(page.getByText(/read-only revision/)).toBeVisible();
  await expect(task.getByRole('heading', { level: 3 })).toHaveText('Invoice matching · pending');
});

test('submits a merge and a split with explicit source lineage', async ({ page }) => {
  const commands = await mockReview(page);
  for (const title of tasks.map(task => task.title)) {
    await page.getByRole('region', { name: title, exact: true }).getByRole('checkbox', { name: 'Mark for merge' }).check();
  }
  const reason = page.getByLabel('Reason for next decision');
  await reason.fill('Compare linked scopes');
  await page.getByText('Merge marked tasks (2)', { exact: true }).click();
  await page.getByLabel('Merged task title').fill('Invoice workflow');
  await page.getByRole('button', { name: 'Merge marked tasks' }).click();
  const merged = page.getByRole('region', { name: 'Invoice workflow' });
  await expect(merged).toBeVisible();
  await merged.getByText('Split task').click();
  await merged.getByLabel('Child 1 title').fill('Validate invoice');
  await merged.getByLabel('Child 2 title').fill('Triage exceptions');
  await merged.locator('input[name="sources0"][value="10"]').check();
  await merged.locator('input[name="sources1"][value="20"]').check();
  await reason.fill('Different investigation objectives');
  await merged.getByRole('button', { name: 'Save split' }).click();
  await expect(page.getByRole('region', { name: 'Triage exceptions' })).toBeVisible();
  expect(commands[0].task_ids).toEqual(['proposal-1', 'proposal-2']);
  expect(commands[1].children).toEqual([{ title: 'Validate invoice', source_ids: [10] }, { title: 'Triage exceptions', source_ids: [20] }]);
});
