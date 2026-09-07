import { defineConfig, devices } from '@playwright/test';

// The report reader is the one surface in this app whose correctness lives in
// browser behaviour rather than in a pure function: it drives a same-origin
// iframe, scales it to fit, and tracks which page is in view. None of that can
// be asserted from a request spec, so it gets a real browser.
//
// Runs against the compose stack, so `docker compose up` is the only setup.
export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  reporter: [['list']],
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:5173',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    viewport: { width: 1440, height: 900 },
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
