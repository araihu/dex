import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './test',
  testMatch: '**/*.spec.ts',
  outputDir: './test-results',
  snapshotPathTemplate: '{testDir}/screenshots/araihu/{arg}{ext}',
  fullyParallel: false,
  workers: 1,
  expect: {
    toHaveScreenshot: {
      animations: 'disabled',
      caret: 'hide',
    },
  },
  use: {
    baseURL: process.env.DEX_TEST_BASE_URL ?? 'http://127.0.0.1:5556',
  },
});
