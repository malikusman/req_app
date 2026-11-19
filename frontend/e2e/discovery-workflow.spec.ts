import { test, expect } from '@playwright/test';

test('a blocked saved answer can be retried without resubmitting employee text', async ({ page }) => {
  let posts = 0;
  let recovered = false;
  await page.addInitScript(() => localStorage.setItem('req_discover_session', JSON.stringify({ link: 'workflow-test', token: 'test-token' })));
  await page.route('**/api/v1/public/discover/messages', async (route) => {
    if (route.request().method() === 'POST') {
      posts++;
      expect(route.request().postDataJSON()).toEqual({ retry: true });
      recovered = true;
    }
    await route.fulfill({ json: {
      messages: [{ id: 1, direction: recovered ? 'outbound' : 'inbound',
        body: recovered ? 'Which HR task do you usually start with?' : 'outlook, Excel and our system',
        message_type: 'text', is_discovery_question: recovered, created_at: new Date().toISOString() }],
      state: { onboarding_step: 'verified', participation_status: 'started', conversation_status: 'discovery',
        question_count: recovered ? 1 : 0, completed: false, discovery_pending: false,
        discovery_error: recovered ? null : 'openai_quota_exceeded' },
    } });
  });
  await page.goto('/discover/workflow-test/chat');
  await expect(page.getByRole('textbox')).toBeDisabled();
  await page.getByRole('button', { name: 'Retry saved answer' }).click();
  await expect(page.getByText('Which HR task do you usually start with?')).toBeVisible();
  await expect(page.getByRole('textbox')).toBeEnabled();
  expect(posts).toBe(1);
});

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
  await expect(page.getByText('Your answer is saved. Retrying shortly…')).toBeVisible();
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


test('typing follows active retry processing and stays hidden while waiting', async ({ page }) => {
  let phase = 'retry_waiting';
  await page.addInitScript(() => localStorage.setItem('req_discover_session', JSON.stringify({ link: 'workflow-test', token: 'test-token' })));
  await page.route('**/api/v1/public/discover/messages', route => route.fulfill({ json: {
    messages: [], state: { onboarding_step: 'verified', participation_status: 'started', conversation_status: 'discovery',
      question_count: 1, completed: false, discovery_pending: phase !== 'idle', discovery_phase: phase },
  } }));
  await page.goto('/discover/workflow-test/chat');
  await expect(page.getByText('Your answer is saved. Retrying shortly…')).toBeVisible();
  await expect(page.getByRole('textbox')).toBeDisabled();
  await expect(page.getByRole('status', { name: 'Assistant is typing' })).toHaveCount(0);
  phase = 'processing';
  await expect(page.getByText('Working on your saved answer…')).toBeVisible();
  await expect(page.getByRole('textbox')).toBeDisabled();
  await expect(page.getByRole('status', { name: 'Assistant is typing' })).toBeVisible();
  phase = 'idle';
  await expect(page.getByRole('textbox')).toBeEnabled();
  await expect(page.getByRole('status', { name: 'Assistant is typing' })).toHaveCount(0);
});


test('uncertain POST retries keep one submission identity after browser refresh', async ({ page }) => {
  let accepted = false;
  let recovered = false;
  let firstFailed = false;
  const ids: string[] = [];
  await page.addInitScript(() => localStorage.setItem('req_discover_session', JSON.stringify({ link: 'transport-test', token: 'test-token' })));
  await page.route('**/api/v1/public/discover/messages*', async route => {
    const request = route.request();
    if (request.method() === 'POST') {
      const body = request.postDataJSON();
      ids.push(body.submission_id);
      expect(body.body).toBe('Recruitment answer');
      if (!firstFailed) {
        firstFailed = true;
        await route.abort('failed');
        return;
      }
      accepted = true;
      recovered = true;
    }
    await route.fulfill({ json: {
      messages: recovered ? [{ id: 2, direction: 'outbound', body: 'Recovered next question?', message_type: 'text', created_at: new Date().toISOString() }] : [],
      state: { onboarding_step: 'verified', conversation_status: 'discovery', completed: false, question_count: recovered ? 1 : 0,
        discovery_pending: false, discovery_phase: 'idle', discovery_state_version: recovered ? 3 : 1,
        submission_received: new URL(request.url()).searchParams.has('submission_id') ? accepted : null },
    } });
  });
  await page.goto('/discover/transport-test/chat');
  await page.getByRole('textbox').fill('Recruitment answer');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.getByText('Your answer is saved on this device. Reconnecting to confirm delivery…')).toBeVisible();
  await page.reload();
  await expect(page.getByText('Recovered next question?')).toBeVisible();
  expect(ids.length).toBe(2);
  expect(ids[0]).toBeTruthy();
  expect(new Set(ids).size).toBe(1);
});


test('accepted POST with lost response is reconciled without resubmission or stale snapshot overwrite', async ({ page }) => {
  let accepted = false;
  let posts = 0;
  let reloadMode = false;
  let releaseOld: (() => void) | undefined;
  const old = new Promise<void>(resolve => { releaseOld = resolve; });
  await page.addInitScript(() => localStorage.setItem('req_discover_session', JSON.stringify({ link: 'accepted-test', token: 'test-token' })));
  await page.route('**/api/v1/public/discover/messages*', async route => {
    const request = route.request();
    const query = new URL(request.url()).searchParams.has('submission_id');
    if (request.method() === 'POST') {
      posts++;
      accepted = true;
      await route.abort('failed');
      return;
    }
    if (reloadMode && !query) {
      await old;
      await route.fulfill({ json: { messages: [], state: { conversation_status: 'discovery', completed: false, discovery_pending: false, discovery_state_version: 1 } } });
      return;
    }
    await route.fulfill({ json: {
      messages: accepted ? [{ id: 3, direction: 'outbound', body: 'Newest question remains', message_type: 'text', created_at: new Date().toISOString() }] : [],
      state: { conversation_status: 'discovery', completed: false, discovery_pending: false, discovery_phase: 'idle', discovery_state_version: accepted ? 5 : 1,
        submission_received: query ? accepted : null },
    } });
    if (reloadMode && query) releaseOld?.();
  });
  await page.goto('/discover/accepted-test/chat');
  await page.getByRole('textbox').fill('Saved answer');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await expect(page.getByText('Your answer is saved on this device. Reconnecting to confirm delivery…')).toBeVisible();
  reloadMode = true;
  await page.reload();
  await expect(page.getByText('Newest question remains')).toBeVisible();
  await expect(page.getByRole('textbox')).toBeEnabled();
  expect(posts).toBe(1);
});
