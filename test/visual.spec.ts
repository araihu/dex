import type { Locator, Page, TestInfo } from '@playwright/test';
import {
  authorizationPath,
  closeAppearance,
  definitelyInvalidTOTP,
  expect,
  openPassword,
  openAppearance,
  readTOTPSecret,
  submitPassword,
  submitTOTP,
  test,
  totp,
  type CreateVirtualAuthenticator,
} from './fixtures/real-dex';
import { assertThemeContrastMatrix, themes } from './fixtures/theme-matrix';

const visualUsers = {
  primary: {
    email: 'visual@example.invalid',
    id: '00000000-0000-4000-8000-000000000004',
  },
  device: {
    email: 'visual-device@example.invalid',
    id: '00000000-0000-4000-8000-000000000005',
  },
  oob: {
    email: 'visual-oob@example.invalid',
    id: '00000000-0000-4000-8000-000000000006',
  },
} as const;

async function enroll(
  page: Page,
  email: string,
  userID: string,
  createVirtualAuthenticator: CreateVirtualAuthenticator,
) {
  await submitPassword(page, email);
  const secret = readTOTPSecret(userID);
  await submitTOTP(page, totp(secret));
  await createVirtualAuthenticator();
  await Promise.all([
    page.waitForURL(/\/approval\?/),
    page.getByRole('button', { name: 'Register Security Key' }).click(),
  ]);
  return secret;
}

async function setAraiHuMode(page: Page, dark: boolean) {
  await openAppearance(page);
  await page.getByLabel('Theme').selectOption('araihu');
  const root = page.locator('html');
  if (await root.evaluate((element) => element.classList.contains('dark')) !== dark) {
    await page.locator('.araihu-mode-button').click();
  }
  await expect(root).toHaveAttribute('data-theme', 'araihu');
  if (dark) await expect(root).toHaveClass(/\bdark\b/);
  else await expect(root).not.toHaveClass(/\bdark\b/);
  await closeAppearance(page);
}

async function captureAraiHu(
  page: Page,
  state: string,
  options: { mask?: Locator[] } = {},
) {
  await assertThemeContrastMatrix(page, state);
  for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    for (const mode of ['light', 'dark'] as const) {
      await setAraiHuMode(page, mode === 'dark');
      await page.evaluate(() => document.fonts.ready);
      await expect(page).toHaveScreenshot(`${state}-${width}-${mode}.png`, {
        fullPage: true,
        mask: options.mask,
      });
    }
  }
}

async function captureOtherThemes(page: Page, testInfo: TestInfo) {
  for (const theme of themes.filter((key) => key !== 'araihu')) {
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      for (const mode of ['light', 'dark'] as const) {
        await openAppearance(page);
        await page.getByLabel('Theme').selectOption(theme);
        const root = page.locator('html');
        if (await root.evaluate((element) => element.classList.contains('dark')) !== (mode === 'dark')) {
          await page.locator('.araihu-mode-button').click();
        }
        await closeAppearance(page);
        const body = await page.screenshot({ fullPage: true, animations: 'disabled' });
        await testInfo.attach(`login-${theme}-${width}-${mode}`, { body, contentType: 'image/png' });
      }
    }
  }
}

test('AraiHu public and error surfaces have committed responsive baselines', async ({ page, browserErrors }) => {
  test.setTimeout(180_000);
  await page.goto(authorizationPath());
  await captureAraiHu(page, 'login');

  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await captureAraiHu(page, 'password');
  browserErrors.allowHTTPError({ pathname: '/auth/local/login', status: 401, count: 1 });
  await submitPassword(page, visualUsers.primary.email, 'wrong-password');
  await expect(page.locator('#login-error')).toBeVisible();
  await captureAraiHu(page, 'password-invalid');

  browserErrors.allowHTTPError({ pathname: '/device', status: 400, count: 1 });
  await page.goto('/device?user_code=BAD-CODE&invalid=true');
  await captureAraiHu(page, 'device-invalid');

  browserErrors.allowHTTPError({ pathname: '/auth', status: 400, count: 1 });
  await page.goto('/auth');
  await captureAraiHu(page, 'error-bad-request');

  await page.context().clearCookies();
  await page.goto('/');
  await captureAraiHu(page, 'home-signed-out');
  await page.goto('/logout');
  await captureAraiHu(page, 'logout-session-not-found');
});

test('other allowlisted themes retain login evidence as test artifacts', async ({ page }, testInfo) => {
  test.setTimeout(90_000);
  await page.goto(authorizationPath());
  await captureOtherThemes(page, testInfo);
});

test('AraiHu TOTP, WebAuthn, and approval states have committed baselines', async ({
  page,
  browserErrors,
  createVirtualAuthenticator,
}) => {
  test.setTimeout(240_000);
  await openPassword(page, authorizationPath({ scopes: ['openid', 'profile', 'email'] }));
  await expect(page.getByRole('heading', { name: 'Log in to Your Account' })).toBeVisible();
  await submitPassword(page, visualUsers.primary.email);
  const qr = page.getByRole('img', { name: 'QR code' });
  await expect(qr).toHaveAttribute('src', /^data:image\/png;base64,/);
  await expect(qr).toHaveAttribute('alt', 'QR code');
  await expect(qr).toHaveAttribute('width', '200');
  await expect(qr).toHaveAttribute('height', '200');
  expect(await qr.boundingBox()).toMatchObject({ width: 200, height: 200 });
  await captureAraiHu(page, 'totp-enrollment', { mask: [qr] });

  const secret = readTOTPSecret(visualUsers.primary.id);
  browserErrors.allowHTTPError({ pathname: '/mfa/totp', status: 401, count: 1 });
  await submitTOTP(page, definitelyInvalidTOTP(secret));
  await captureAraiHu(page, 'totp-enrollment-invalid', { mask: [page.getByRole('img', { name: 'QR code' })] });
  await submitTOTP(page, totp(secret, -1));
  await captureAraiHu(page, 'webauthn-register');

  let failBegin = true;
  browserErrors.allowHTTPError({ pathname: '/mfa/webauthn/register/begin', status: 503, count: 1 });
  await page.route('**/mfa/webauthn/register/begin?**', async (route) => {
    if (!failBegin) return route.continue();
    failBegin = false;
    await route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":"test outage"}' });
  });
  await page.getByRole('button', { name: 'Register Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toContainText('status 503');
  await captureAraiHu(page, 'webauthn-register-server-error');
  await page.unroute('**/mfa/webauthn/register/begin?**');

  const authenticator = await createVirtualAuthenticator(false);
  await page.getByRole('button', { name: 'Register Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toContainText('cancelled or timed out', { timeout: 5_000 });
  await captureAraiHu(page, 'webauthn-register-timeout');
  await authenticator.setPresence(true);

  const registerURL = page.url();
  const wrongOrigin = new URL(registerURL);
  wrongOrigin.hostname = '127.0.0.1';
  await page.goto(wrongOrigin.href);
  await page.getByRole('button', { name: 'Register Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toContainText('not allowed on this domain');
  await captureAraiHu(page, 'webauthn-register-security-error');

  await page.goto(registerURL);
  await Promise.all([
    page.waitForURL(/\/approval\?/),
    page.getByRole('button', { name: 'Register Security Key' }).click(),
  ]);
  await captureAraiHu(page, 'approval-scopes');

  await page.context().clearCookies();
  await openPassword(page, authorizationPath({ scopes: ['openid'], prompt: 'consent' }));
  await submitPassword(page, visualUsers.primary.email);
  await captureAraiHu(page, 'totp-verification');

  let releaseLogin!: () => void;
  const gate = new Promise<void>((resolve) => { releaseLogin = resolve; });
  await page.route('**/mfa/webauthn/login/begin?**', async (route) => {
    await gate;
    await route.continue();
  });
  await submitTOTP(page, totp(secret));
  await expect(page.locator('#webauthn-working')).toBeVisible();
  await captureAraiHu(page, 'webauthn-login-working');
  const approval = page.waitForURL(/\/approval\?/);
  releaseLogin();
  await approval;
  await page.unroute('**/mfa/webauthn/login/begin?**');
  await captureAraiHu(page, 'approval-no-scopes');
});

test('AraiHu device, signed-in home, and logout states have committed baselines', async ({
  page,
  createVirtualAuthenticator,
}) => {
  test.setTimeout(180_000);
  const response = await page.request.post('/device/code', {
    form: { client_id: 'araihu-test', client_secret: 'local-test-client-secret', scope: 'openid profile' },
  });
  expect(response.ok()).toBe(true);
  const device = await response.json() as { user_code: string; verification_uri_complete: string };
  expect(device.user_code).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
  await page.goto(device.verification_uri_complete);
  const deviceCode = page.locator('#user_code');
  await expect(deviceCode).toHaveValue(device.user_code);
  await deviceCode.evaluate((input: HTMLInputElement) => { input.value = 'ABCD-EFGH'; });
  await captureAraiHu(page, 'device-entry');
  await deviceCode.fill(device.user_code);
  await page.getByRole('button', { name: 'Submit' }).click();
  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await enroll(page, visualUsers.device.email, visualUsers.device.id, createVirtualAuthenticator);
  await page.getByRole('button', { name: 'Grant Access' }).click();
  await expect(page.getByRole('heading', { name: 'Login Successful for AraiHu Test Client' })).toBeVisible();
  await captureAraiHu(page, 'device-success');

  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'visual-device-user' })).toBeVisible();
  const times = page.locator('time[datetime]');
  await expect(times).toHaveCount(2);
  for (const time of await times.all()) {
    const datetime = await time.getAttribute('datetime');
    const visibleText = await time.textContent();
    expect(datetime).toMatch(/\S+/);
    expect(Number.isNaN(Date.parse(datetime!))).toBe(false);
    expect(visibleText).toMatch(/\S+/);
  }
  await times.nth(0).evaluate((element) => { element.textContent = 'Jan 1, 2000, 12:00 AM'; });
  await times.nth(1).evaluate((element) => { element.textContent = 'Jan 1, 2000, 12:30 AM'; });
  const signedInFrom = page.locator('.dex-fact').filter({ has: page.getByText('Signed in from', { exact: true }) }).locator('dd');
  const browser = page.locator('.dex-fact').filter({ has: page.getByText('Browser', { exact: true }) }).locator('dd');
  await expect(signedInFrom).toHaveText(/\S+/);
  await expect(browser).toHaveText(/\S+/);
  await signedInFrom.evaluate((element) => { element.textContent = '192.0.2.1'; });
  await browser.evaluate((element) => { element.textContent = 'Deterministic test browser'; });
  await captureAraiHu(page, 'home-signed-in');
  await page.goto('/logout');
  await captureAraiHu(page, 'logout-confirmation');
  await page.getByRole('button', { name: 'Log Out' }).click();
  await captureAraiHu(page, 'logout-complete');
});

test('AraiHu OOB completion has committed responsive baselines', async ({
  page,
  createVirtualAuthenticator,
}) => {
  test.setTimeout(180_000);
  await openPassword(page, authorizationPath({
    redirectURI: 'urn:ietf:wg:oauth:2.0:oob', scopes: ['openid'], prompt: 'consent',
  }));
  await expect(page.getByRole('heading', { name: 'Log in to Your Account' })).toBeVisible();
  await enroll(page, visualUsers.oob.email, visualUsers.oob.id, createVirtualAuthenticator);
  await page.getByRole('button', { name: 'Grant Access' }).click();
  await expect(page.getByRole('heading', { name: 'Login Successful' })).toBeVisible();
  const oobCode = page.locator('input.theme-form-input');
  await expect(oobCode).toHaveValue(/\S+/);
  await oobCode.evaluate((input: HTMLInputElement) => { input.value = 'TEST-OOB-CODE'; });
  await captureAraiHu(page, 'oob-complete');
});

test('exact visual gate rejects an unrelated one-pixel regression', async ({ page }, testInfo) => {
  test.skip(
    !['missing', 'none'].includes(testInfo.config.updateSnapshots),
    'mutation assertions must never rewrite their reference',
  );
  await page.setViewportSize({ width: 390, height: 900 });
  await page.goto(authorizationPath());
  await setAraiHuMode(page, false);
  await page.evaluate(() => document.fonts.ready);
  await expect(page).toHaveScreenshot('login-390-light.png', { fullPage: true });

  await page.locator('body').evaluate((body) => {
    const mutation = document.createElement('span');
    mutation.setAttribute('aria-hidden', 'true');
    Object.assign(mutation.style, {
      background: 'rgb(255, 0, 255)',
      height: '1px',
      left: '0',
      pointerEvents: 'none',
      position: 'fixed',
      top: '0',
      width: '1px',
      zIndex: '2147483647',
    });
    body.append(mutation);
  });

  let failure: unknown;
  try {
    await expect(page).toHaveScreenshot('login-390-light.png', { fullPage: true, timeout: 1_000 });
  } catch (error) {
    failure = error;
  }
  expect(failure).toBeInstanceOf(Error);
  expect((failure as Error).message).toMatch(/pixels?.*different/);
});
