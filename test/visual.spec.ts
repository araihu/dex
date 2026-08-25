import { createHmac } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';
import { themes } from './fixtures/theme-matrix';

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

function baseURL() {
  const value = process.env.DEX_TEST_BASE_URL;
  assert.ok(value, 'DEX_TEST_BASE_URL is required; run scripts/test-image.sh');
  return value;
}

function authorizationPath(options: { scopes?: string[]; redirectURI?: string; prompt?: string } = {}) {
  const query = new URLSearchParams({
    client_id: 'araihu-test',
    redirect_uri: options.redirectURI ?? new URL('/client/callback', baseURL()).href,
    response_type: 'code',
    scope: (options.scopes ?? ['openid']).join(' '),
  });
  if (options.prompt) query.set('prompt', options.prompt);
  return `/auth?${query}`;
}

async function openPassword(page: Page, path = authorizationPath()) {
  await page.goto(path);
  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await expect(page.getByRole('heading', { name: 'Log in to Your Account' })).toBeVisible();
}

async function submitPassword(page: Page, email: string, password = 'password') {
  await page.getByLabel('Email Address').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Login' }).click();
}

function readSecret(userID: string) {
  const database = process.env.DEX_TEST_DB;
  assert.ok(database, 'DEX_TEST_DB is required; run scripts/test-image.sh');
  const sql = `select cast(mfa_secrets as text) from user_identity where user_id = '${userID}' and connector_id = 'local';`;
  const output = execFileSync('/usr/bin/sqlite3', ['-readonly', '-cmd', '.timeout 5000', database, sql], {
    encoding: 'utf8',
  }).trim();
  const secrets = JSON.parse(output) as Record<string, { secret: string }>;
  assert.ok(secrets['totp-1']?.secret, `TOTP secret missing for ${userID}`);
  return secrets['totp-1'].secret;
}

function decodeBase32(value: string) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = 0;
  let accumulator = 0;
  const output: number[] = [];
  for (const character of value.toUpperCase().replaceAll('=', '')) {
    const digit = alphabet.indexOf(character);
    assert.notEqual(digit, -1);
    accumulator = (accumulator << 5) | digit;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.push((accumulator >>> bits) & 0xff);
    }
  }
  return Buffer.from(output);
}

function totp(secretURL: string, offset = 0) {
  const secret = new URL(secretURL).searchParams.get('secret');
  assert.ok(secret);
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30_000) + offset));
  const digest = createHmac('sha1', decodeBase32(secret)).update(message).digest();
  const index = digest[digest.length - 1] & 0x0f;
  return ((digest.readUInt32BE(index) & 0x7fffffff) % 1_000_000).toString().padStart(6, '0');
}

function invalidTOTP(secretURL: string) {
  const valid = new Set([-1, 0, 1].map((offset) => totp(secretURL, offset)));
  for (let value = 0; value < 10; value += 1) {
    const candidate = value.toString().padStart(6, '0');
    if (!valid.has(candidate)) return candidate;
  }
  throw new Error('could not choose an invalid TOTP code');
}

async function submitTOTP(page: Page, code: string) {
  await page.getByLabel('One-time code').fill(code);
  await page.getByRole('button', { name: 'Verify' }).click();
}

async function addVirtualAuthenticator(page: Page, automaticPresenceSimulation = true) {
  const session = await page.context().newCDPSession(page);
  await session.send('WebAuthn.enable');
  const { authenticatorId } = await session.send('WebAuthn.addVirtualAuthenticator', {
    options: {
      protocol: 'ctap2',
      transport: 'usb',
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      automaticPresenceSimulation,
    },
  });
  return { session, authenticatorId };
}

async function enroll(page: Page, email: string, userID: string) {
  await submitPassword(page, email);
  const secret = readSecret(userID);
  await submitTOTP(page, totp(secret, -1));
  const authenticator = await addVirtualAuthenticator(page);
  await Promise.all([
    page.waitForURL(/\/approval\?/),
    page.getByRole('button', { name: 'Register Security Key' }).click(),
  ]);
  return { secret, ...authenticator };
}

async function setAraiHuMode(page: Page, dark: boolean) {
  await page.getByLabel('Tema').selectOption('araihu');
  const root = page.locator('html');
  if (await root.evaluate((element) => element.classList.contains('dark')) !== dark) {
    await page.locator('.araihu-mode-button').click();
  }
  await expect(root).toHaveAttribute('data-theme', 'araihu');
  if (dark) await expect(root).toHaveClass(/\bdark\b/);
  else await expect(root).not.toHaveClass(/\bdark\b/);
}

async function captureAraiHu(
  page: Page,
  state: string,
  options: { mask?: Locator[]; dynamicText?: boolean } = {},
) {
  for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    for (const mode of ['light', 'dark'] as const) {
      await setAraiHuMode(page, mode === 'dark');
      await page.evaluate(() => document.fonts.ready);
      await expect(page).toHaveScreenshot(`${state}-${width}-${mode}.png`, {
        fullPage: true,
        mask: options.mask,
        maxDiffPixelRatio: options.dynamicText ? 0.005 : 0,
      });
    }
  }
}

async function captureOtherThemes(page: Page, testInfo: TestInfo) {
  for (const theme of themes.filter((key) => key !== 'araihu')) {
    await page.getByLabel('Tema').selectOption(theme);
    for (const width of [390, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      for (const mode of ['light', 'dark'] as const) {
        const root = page.locator('html');
        if (await root.evaluate((element) => element.classList.contains('dark')) !== (mode === 'dark')) {
          await page.locator('.araihu-mode-button').click();
        }
        const body = await page.screenshot({ fullPage: true, animations: 'disabled' });
        await testInfo.attach(`login-${theme}-${width}-${mode}`, { body, contentType: 'image/png' });
      }
    }
  }
}

test('AraiHu public and error surfaces have committed responsive baselines', async ({ page }) => {
  test.setTimeout(90_000);
  await page.goto(authorizationPath());
  await captureAraiHu(page, 'login');

  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await captureAraiHu(page, 'password');
  await submitPassword(page, visualUsers.primary.email, 'wrong-password');
  await expect(page.locator('#login-error')).toBeVisible();
  await captureAraiHu(page, 'password-invalid');

  await page.goto('/device?user_code=BAD-CODE&invalid=true');
  await captureAraiHu(page, 'device-invalid');

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

test('AraiHu TOTP, WebAuthn, and approval states have committed baselines', async ({ page }) => {
  test.setTimeout(120_000);
  await openPassword(page, authorizationPath({ scopes: ['openid', 'profile', 'email'] }));
  await submitPassword(page, visualUsers.primary.email);
  const qr = page.getByRole('img', { name: 'QR code' });
  await expect(qr).toHaveAttribute('src', /^data:image\/png;base64,/);
  await expect(qr).toHaveAttribute('alt', 'QR code');
  await expect(qr).toHaveAttribute('width', '200');
  await expect(qr).toHaveAttribute('height', '200');
  expect(await qr.boundingBox()).toMatchObject({ width: 200, height: 200 });
  await captureAraiHu(page, 'totp-enrollment', { mask: [qr] });

  const secret = readSecret(visualUsers.primary.id);
  await submitTOTP(page, invalidTOTP(secret));
  await captureAraiHu(page, 'totp-enrollment-invalid', { mask: [page.getByRole('img', { name: 'QR code' })] });
  await submitTOTP(page, totp(secret, -1));
  await captureAraiHu(page, 'webauthn-register');

  let failBegin = true;
  await page.route('**/mfa/webauthn/register/begin?**', async (route) => {
    if (!failBegin) return route.continue();
    failBegin = false;
    await route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":"test outage"}' });
  });
  await page.getByRole('button', { name: 'Register Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toContainText('status 503');
  await captureAraiHu(page, 'webauthn-register-server-error');
  await page.unroute('**/mfa/webauthn/register/begin?**');

  const { session, authenticatorId } = await addVirtualAuthenticator(page, false);
  await page.getByRole('button', { name: 'Register Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toContainText('cancelled or timed out', { timeout: 5_000 });
  await captureAraiHu(page, 'webauthn-register-timeout');
  await session.send('WebAuthn.setAutomaticPresenceSimulation', { authenticatorId, enabled: true });

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

test('AraiHu device, signed-in home, and logout states have committed baselines', async ({ page }) => {
  test.setTimeout(120_000);
  const response = await page.request.post('/device/code', {
    form: { client_id: 'araihu-test', client_secret: 'local-test-client-secret', scope: 'openid profile' },
  });
  const device = await response.json() as { verification_uri_complete: string };
  await page.goto(device.verification_uri_complete);
  await captureAraiHu(page, 'device-entry', { dynamicText: true });
  await page.getByRole('button', { name: 'Submit' }).click();
  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await enroll(page, visualUsers.device.email, visualUsers.device.id);
  await page.getByRole('button', { name: 'Grant Access' }).click();
  await expect(page.getByRole('heading', { name: 'Login Successful for AraiHu Test Client' })).toBeVisible();
  await captureAraiHu(page, 'device-success');

  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'visual-device-user' })).toBeVisible();
  await captureAraiHu(page, 'home-signed-in', { dynamicText: true });
  await page.goto('/logout');
  await captureAraiHu(page, 'logout-confirmation');
  await page.getByRole('button', { name: 'Log Out' }).click();
  await captureAraiHu(page, 'logout-complete');
});

test('AraiHu OOB completion has committed responsive baselines', async ({ page }) => {
  test.setTimeout(120_000);
  await openPassword(page, authorizationPath({
    redirectURI: 'urn:ietf:wg:oauth:2.0:oob', scopes: ['openid'], prompt: 'consent',
  }));
  await enroll(page, visualUsers.oob.email, visualUsers.oob.id);
  await page.getByRole('button', { name: 'Grant Access' }).click();
  await expect(page.getByRole('heading', { name: 'Login Successful' })).toBeVisible();
  await captureAraiHu(page, 'oob-complete', { dynamicText: true });
});
