import { expect, test } from '@playwright/test';

async function observerModule() {
  return import('./fixtures/real-dex').catch(() => ({}));
}

test('browser observer accepts only an exact endpoint status and count allowance', async () => {
  const helper = await observerModule();
  expect(helper.BrowserErrorObserver).toBeDefined();
  const observer = new helper.BrowserErrorObserver!();
  observer.allowHTTPError({ pathname: '/mfa/webauthn/login/begin', status: 503, count: 1 });
  observer.recordConsole(
    'error',
    'Failed to load resource: the server responded with a status of 503 (Service Unavailable)',
    'http://localhost:5556/mfa/webauthn/login/begin?req=test',
  );

  expect(() => observer.verify()).not.toThrow();
});

test('browser observer rejects unexpected, mismatched, excess, and page errors', async () => {
  const helper = await observerModule();
  expect(helper.BrowserErrorObserver).toBeDefined();
  const failures = [
    { pathname: '/unexpected', status: 503, count: 1, repeats: 1, pageError: false },
    { pathname: '/mfa/webauthn/login/begin', status: 500, count: 1, repeats: 1, pageError: false },
    { pathname: '/mfa/webauthn/login/begin', status: 503, count: 1, repeats: 2, pageError: false },
    { pathname: '/mfa/webauthn/login/begin', status: 503, count: 1, repeats: 0, pageError: true },
  ];

  for (const mutation of failures) {
    const observer = new helper.BrowserErrorObserver!();
    observer.allowHTTPError({
      pathname: '/mfa/webauthn/login/begin',
      status: 503,
      count: mutation.count,
    });
    for (let index = 0; index < mutation.repeats; index += 1) {
      observer.recordConsole(
        'error',
        `Failed to load resource: the server responded with a status of ${mutation.status} (Test)`,
        `http://localhost:5556${mutation.pathname}?req=test`,
      );
    }
    if (mutation.pageError) observer.recordPageError(new Error('mutation'));
    expect(() => observer.verify(), JSON.stringify(mutation)).toThrow();
  }
});
