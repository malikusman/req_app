import { test, expect } from '@playwright/test';

test('a saved answer recovers through reads without another submission or manual retry UI', async ({ page }) => {
  let posts = 0;
  let recovered = false;
  const state = { onboarding_step: 'verified', participation_status: 'started', conversation_status: 'discovery',
    question_count: 1, completed: false, discovery_pending: true };
  const messages = [{ id: 1, direction: 'inbound', body: 'I use Excel and SAP.', message_type: 'text',
    is_discovery_question: false, created_at: new Date().toISOString() }];
  await page.addInitScript(() => localStorage.setItem('req_discover_session', JSON.stringify({ link: 'workflow-test', token: 'test-token' })));
  await page.route('**/api/v1/public/discover/messages', async (route) => {
    if (route.request().method() === 'POST') posts++;
    await route.fulfill({ json: { state: { ...state, discovery_pending: !recovered },
      messages: recovered ? [...messages, { ...messages[0], id: 2, direction: 'outbound', body: 'What happens to unmatched payments?' }] : messages } });
  });
  await page.goto('/discover/workflow-test/chat');
  await expect(page.getByText('Your answer is saved — continuing automatically…')).toBeVisible();
  recovered = true;
  await expect(page.getByText('What happens to unmatched payments?')).toBeVisible();
  expect(posts).toBe(0);
  await expect(page.getByRole('button', { name: /retry saved answer/i })).toHaveCount(0);
});

test('an incomplete terminal interview is not presented as successful', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('req_discover_session', JSON.stringify({ link: 'workflow-test', token: 'test-token' })));
  await page.route('**/api/v1/public/discover/messages', (route) => route.fulfill({ json: {
    messages: [], state: { onboarding_step: 'verified', participation_status: 'started', conversation_status: 'completed',
      question_count: 14, completed: true, discovery_outcome: 'needs_follow_up' },
  } }));
  await page.goto('/discover/workflow-test/chat');
  await expect(page.getByText('Answers saved — workflow details need follow-up')).toBeVisible();
  await expect(page.getByText('Interview complete — but you can always add more anytime.')).toHaveCount(0);
});
