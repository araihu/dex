import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import type { Locator, Page } from '@playwright/test';
import { assertCriticalAxe } from './fixtures/inherited-accessibility';
import {
  authorizationPath,
  baseURL,
  definitelyInvalidTOTP,
  expect,
  openAppearance,
  readTOTPSecret,
  submitPassword,
  submitTOTP,
  test,
  totp,
  type CreateVirtualAuthenticator,
} from './fixtures/real-dex';
import { assertThemeMatrix } from './fixtures/theme-matrix';

const templateNames = [
  'approval.html',
  'device.html',
  'device_success.html',
  'error.html',
  'home.html',
  'login.html',
  'logout.html',
  'oob.html',
  'password.html',
  'totp_verify.html',
  'webauthn_verify.html',
] as const;

type TemplateName = typeof templateNames[number];

const lockedTemplates = Object.fromEntries(await Promise.all(templateNames.map(async (name) => [
  name,
  await readFile(new URL(`../.cache/sources/dex/web/templates/${name}`, import.meta.url), 'utf8'),
]))) as Record<TemplateName, string>;

function locked(name: TemplateName, literal: string) {
  assert.ok(lockedTemplates[name].includes(literal), `${name} no longer contains ${JSON.stringify(literal)}`);
  return literal;
}

const expectedCSP = [
  "default-src 'self'",
  "base-uri 'none'",
  "connect-src 'self'",
  "font-src 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "img-src 'self' data:",
  "object-src 'none'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
].join('; ');

async function expectAttributes(locator: Locator, attributes: Record<string, string>) {
  for (const [name, value] of Object.entries(attributes)) {
    await expect(locator).toHaveAttribute(name, value);
  }
}

async function openPasswordWithAssertions(page: Page, path = authorizationPath()) {
  await page.goto(path);
  await expect(page.getByRole('heading', { name: 'Log in to AraiHu Dex' })).toBeVisible();
  await assertCriticalAxe(page);
  await assertThemeMatrix(page);
  await expect(page.getByRole('link', { name: 'Log in with Email' })).toBeVisible();
  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await expect(page.getByRole('heading', { name: 'Log in to Your Account' })).toBeVisible();
  await assertPasswordForm(page);
}

async function assertPasswordForm(page: Page, username = '') {
  locked('password.html', '<form method="post" action="{{ .PostURL }}">');
  locked('password.html', 'required id="login" name="login" type="text"');
  locked('password.html', 'required id="password" name="password" type="password"');
  locked('password.html', 'type="checkbox" name="remember_me"');
  locked('password.html', 'id="submit-login" type="submit"');

  const current = new URL(page.url());
  const form = page.locator('form');
  await expectAttributes(form, { method: 'post', action: `${current.pathname}${current.search}` });
  await expectAttributes(page.getByLabel('Email Address'), {
    id: 'login', name: 'login', required: '', tabindex: '1', type: 'text',
  });
  await expect(page.getByLabel('Email Address')).toHaveValue(username);
  await expectAttributes(page.getByLabel('Password'), {
    id: 'password', name: 'password', required: '', tabindex: '2', type: 'password',
  });
  await expectAttributes(page.getByLabel('Remember me'), {
    name: 'remember_me', tabindex: '3', type: 'checkbox',
  });
  await expectAttributes(page.getByRole('button', { name: 'Login' }), {
    id: 'submit-login', tabindex: '4', type: 'submit',
  });
  await assertCriticalAxe(page);
}

async function assertTOTPPage(page: Page, enrollment: boolean, invalid = false) {
  locked('totp_verify.html', '<form method="post" action="{{ .PostURL }}">');
  locked('totp_verify.html', 'required id="totp" name="totp" type="text"');
  locked('totp_verify.html', 'inputmode="numeric" pattern="[0-9]*" maxlength="6"');
  locked('totp_verify.html', 'autocomplete="one-time-code"');
  locked('totp_verify.html', 'id="submit-login" type="submit"');

  await expect(page.getByRole('heading', { name: 'Two-factor authentication' })).toBeVisible();
  const current = new URL(page.url());
  await expectAttributes(page.locator('form'), { method: 'post', action: `${current.pathname}${current.search}` });
  await expectAttributes(page.getByLabel('One-time code'), {
    autocomplete: 'one-time-code', id: 'totp', inputmode: 'numeric', maxlength: '6',
    name: 'totp', pattern: '[0-9]*', required: '', tabindex: '1', type: 'text',
  });
  await expect(page.getByLabel('One-time code')).toBeFocused();
  await expectAttributes(page.getByRole('button', { name: 'Verify' }), {
    id: 'submit-login', tabindex: '2', type: 'submit',
  });
  if (enrollment) {
    locked('totp_verify.html', '<img src="data:image/png;base64,{{ .QRCode }}" alt="QR code" width="200" height="200"/>');
    const qr = page.getByRole('img', { name: 'QR code' });
    await expect(qr).toHaveAttribute('src', /^data:image\/png;base64,/);
    await expectAttributes(qr, { alt: 'QR code', height: '200', width: '200' });
    expect(await qr.boundingBox()).toMatchObject({ width: 200, height: 200 });
  } else {
    await expect(page.getByRole('img', { name: 'QR code' })).toHaveCount(0);
    await expect(page.getByText('AraiHu Dex Test')).toBeVisible();
  }
  if (invalid) await expect(page.locator('#login-error')).toContainText('Invalid code');
  await assertCriticalAxe(page);
}

async function assertWebAuthnPage(page: Page, mode: 'register' | 'login') {
  locked('webauthn_verify.html', 'onclick="startWebAuthn()"');
  locked('webauthn_verify.html', 'fetch(basePath + "/mfa/webauthn/register/begin?"');
  locked('webauthn_verify.html', 'fetch(basePath + "/mfa/webauthn/register/finish?"');
  locked('webauthn_verify.html', 'fetch(basePath + "/mfa/webauthn/login/begin?"');
  locked('webauthn_verify.html', 'fetch(basePath + "/mfa/webauthn/login/finish?"');

  await expect(page.getByRole('heading', {
    name: mode === 'register' ? 'Register security key' : 'Two-factor authentication',
  })).toBeVisible();
  await expect(page.locator('form')).toHaveCount(0);
  await expect(page.locator('#webauthn-btn')).toHaveAttribute('type', 'button');
  await assertCriticalAxe(page);
}

function assertWebAuthnRequests(requests: Array<{ method: string; url: string }>, mode: 'register' | 'login') {
  for (const path of [`/mfa/webauthn/${mode}/begin`, `/mfa/webauthn/${mode}/finish`]) {
    const matching = requests.filter(({ url }) => new URL(url).pathname === path);
    expect(matching, `${path} request count`).toHaveLength(path.endsWith('/begin') ? 4 : 1);
    for (const request of matching) {
      expect(request.method).toBe('POST');
      const query = new URL(request.url).searchParams;
      expect(query.get('req')).toMatch(/\S+/);
      expect(query.get('hmac')).toMatch(/\S+/);
      expect(query.get('authenticator')).toBe('webauthn-1');
    }
  }
  expect(requests, `${mode} WebAuthn request total`).toHaveLength(5);
}

async function assertApproval(page: Page, scopes: string[]) {
  locked('approval.html', '<form method="post">');
  locked('approval.html', '<input type="hidden" name="req" value="{{ .AuthReqID }}"/>');
  locked('approval.html', '<input type="hidden" name="approval" value="approve">');
  locked('approval.html', '<input type="hidden" name="approval" value="rejected">');

  await expect(page.getByRole('heading', { name: 'Grant Access' })).toBeVisible();
  const forms = page.locator('form');
  await expect(forms).toHaveCount(2);
  const req = new URL(page.url()).searchParams.get('req');
  assert.ok(req);
  for (const form of await forms.all()) {
    await expect(form).toHaveAttribute('method', 'post');
    await expect(form).not.toHaveAttribute('action', /.+/);
    await expect(form.locator('input[name="req"]')).toHaveValue(req);
  }
  await expect(forms.nth(0).locator('input[name="approval"]')).toHaveValue('approve');
  await expect(forms.nth(1).locator('input[name="approval"]')).toHaveValue('rejected');
  await expect(page.getByRole('button', { name: 'Grant Access' })).toHaveAttribute('type', 'submit');
  await expect(page.getByRole('button', { name: 'Cancel' })).toHaveAttribute('type', 'submit');
  if (scopes.length) {
    await expect(page.locator('.dex-list li')).toHaveText(scopes);
  } else {
    await expect(page.getByText('has not requested any personal information')).toBeVisible();
    await expect(page.locator('.dex-list')).toHaveCount(0);
  }
  await assertCriticalAxe(page);
}

async function enrollSimple(
  page: Page,
  email: string,
  userID: string,
  createVirtualAuthenticator: CreateVirtualAuthenticator,
) {
  await submitPassword(page, email);
  await assertTOTPPage(page, true);
  const secret = readTOTPSecret(userID);
  await submitTOTP(page, totp(secret, -1));
  await assertWebAuthnPage(page, 'register');
  await createVirtualAuthenticator();
  await Promise.all([
    page.waitForURL(/\/approval\?/),
    page.getByRole('button', { name: 'Register Security Key' }).click(),
  ]);
}

test('real login, password error, CSP, and overlay scripts preserve locked semantics', async ({ page, browserErrors }) => {
  const response = await page.goto(authorizationPath({ scopes: ['openid', 'profile', 'email'] }));
  expect(response?.headers()['content-security-policy']).toBe(expectedCSP);
  locked('login.html', '<a href="{{ $c.URL }}" class="dex-btn dex-btn-provider theme-btn-provider">');
  await expect(page.getByRole('heading', { name: 'Log in to AraiHu Dex' })).toBeVisible();
  await assertCriticalAxe(page);
  await expect(page.getByRole('link', { name: 'Log in with Email' })).toHaveAttribute('href', /\/auth\/local\?/);
  await expect(page.locator('form')).toHaveCount(0);
  await expect(page.locator('img.theme-navbar__logo')).toHaveAttribute('alt', 'AraiHu Dex');
  await expect(page.locator('img.theme-navbar__logo')).toHaveAttribute('src', 'theme/logo.png');
  const overlayScripts = await page.locator('script[src$="theme-default.js"], script[src$="appearance.js"]').evaluateAll((scripts) => scripts.map((script) => ({
    src: script.getAttribute('src'), text: script.textContent,
  })));
  expect(overlayScripts).toEqual([
    { src: 'static/theme-default.js', text: '' },
    { src: 'static/appearance.js', text: '' },
  ]);

  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await assertPasswordForm(page);
  await expect(page.getByLabel('Email Address')).toBeFocused();
  await assertThemeMatrix(page);
  browserErrors.allowHTTPError({ pathname: '/auth/local/login', status: 401, count: 1 });
  await submitPassword(page, 'test@example.invalid', 'wrong-password');
  await expect(page.locator('#login-error')).toHaveText('Invalid Email Address and password.');
  await assertPasswordForm(page, 'test@example.invalid');
  await expect(page.getByLabel('Password')).toBeFocused();
});

test('real storage choices and exceptions leave authentication semantics intact', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await openPasswordWithAssertions(page);
  const formBefore = await page.locator('form').evaluate((form) => ({
    action: form.getAttribute('action'), method: form.getAttribute('method'), html: form.innerHTML,
  }));
  await openAppearance(page);
  await page.getByLabel('Theme').selectOption('dracula');
  await page.getByRole('button', { name: 'Switch to dark mode' }).press('Enter');
  await page.getByRole('button', { name: 'Not now' }).click();
  await expect(page.getByLabel('Appearance preferences')).toBeHidden();
  await expect(page.getByLabel('Email Address')).toBeFocused();
  expect(await page.locator('form').evaluate((form) => ({
    action: form.getAttribute('action'), method: form.getAttribute('method'), html: form.innerHTML,
  }))).toEqual(formBefore);
  expect(await page.evaluate(() => ({
    theme: localStorage.getItem('theme'), darkMode: localStorage.getItem('darkMode'),
  }))).toEqual({ theme: null, darkMode: null });
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'araihu');
  await expect(page.locator('html')).not.toHaveClass(/\bdark\b/);

  await page.context().addCookies([{ name: 'gt_storage', value: 'allowed', url: baseURL() }]);
  await page.evaluate(() => {
    localStorage.setItem('theme', 'pastel');
    localStorage.setItem('darkMode', 'true');
  });
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'pastel');
  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await openAppearance(page);
  await expect(page.getByLabel('Theme')).toHaveValue('pastel');
  await expect(page.getByRole('button', { name: 'Switch to light mode' })).toHaveAttribute('aria-pressed', 'true');
});

test('real Dex contains cookie and localStorage failures', async ({ page }) => {
  await page.context().addCookies([{ name: 'gt_storage', value: 'allowed', url: baseURL() }]);
  await page.addInitScript(() => {
    Object.defineProperty(window, 'localStorage', {
      value: {
        getItem() { throw new DOMException('blocked', 'SecurityError'); },
        setItem() { throw new DOMException('blocked', 'SecurityError'); },
        removeItem() { throw new DOMException('blocked', 'SecurityError'); },
      },
    });
    Object.defineProperty(Document.prototype, 'cookie', {
      configurable: true,
      get() { throw new DOMException('blocked', 'SecurityError'); },
      set() { throw new DOMException('blocked', 'SecurityError'); },
    });
  });
  await openPasswordWithAssertions(page);
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await openAppearance(page);
  await page.getByLabel('Theme').selectOption('zombie');
  await page.getByRole('button', { name: 'Switch to dark mode' }).click();
  await expect(page.locator('form')).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'zombie');
  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await expect(page.getByLabel('Appearance preferences')).toBeVisible();
});

test('TOTP and WebAuthn registration/login preserve URLs and retryable errors', async ({
  page,
  browserErrors,
  createVirtualAuthenticator,
}) => {
  test.setTimeout(45_000);
  await openPasswordWithAssertions(page, authorizationPath({ scopes: ['openid', 'profile', 'email'] }));
  await submitPassword(page, 'test@example.invalid');
  await assertTOTPPage(page, true);
  await assertThemeMatrix(page);

  const secret = readTOTPSecret('00000000-0000-4000-8000-000000000001');
  browserErrors.allowHTTPError({ pathname: '/mfa/totp', status: 401, count: 1 });
  await submitTOTP(page, definitelyInvalidTOTP(secret));
  await assertTOTPPage(page, true, true);
  await submitTOTP(page, totp(secret, -1));
  await assertWebAuthnPage(page, 'register');
  await assertThemeMatrix(page);

  const registrationRequests: Array<{ method: string; url: string }> = [];
  page.on('request', (request) => {
    if (request.url().includes('/mfa/webauthn/')) registrationRequests.push({ method: request.method(), url: request.url() });
  });
  const authenticator = await createVirtualAuthenticator(true);

  let failBegin = true;
  browserErrors.allowHTTPError({ pathname: '/mfa/webauthn/register/begin', status: 503, count: 1 });
  await page.route('**/mfa/webauthn/register/begin?**', async (route) => {
    if (!failBegin) {
      await route.continue();
      return;
    }
    failBegin = false;
    await route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":"test outage"}' });
  });
  await page.getByRole('button', { name: 'Register Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toHaveText('Registration failed (status 503)');
  await expect(page.getByRole('button', { name: 'Register Security Key' })).toBeVisible();
  await page.unroute('**/mfa/webauthn/register/begin?**');

  await authenticator.setPresence(false);
  await page.getByRole('button', { name: 'Register Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toHaveText('Request was cancelled or timed out. Please try again.', { timeout: 5_000 });
  await expect(page.getByRole('button', { name: 'Register Security Key' })).toBeVisible();
  await authenticator.setPresence(true);

  const registerURL = page.url();
  const wrongOrigin = new URL(registerURL);
  wrongOrigin.hostname = '127.0.0.1';
  await page.goto(wrongOrigin.href);
  await page.getByRole('button', { name: 'Register Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toHaveText('Security key operation not allowed on this domain.');
  await expect(page.getByRole('button', { name: 'Register Security Key' })).toBeVisible();

  await page.goto(registerURL);
  await Promise.all([
    page.waitForURL(/\/approval\?/),
    page.getByRole('button', { name: 'Register Security Key' }).click(),
  ]);
  assertWebAuthnRequests(registrationRequests, 'register');
  await assertApproval(page, ['View basic profile information', 'View your email address']);
  await assertThemeMatrix(page);

  await page.context().clearCookies();
  await openPasswordWithAssertions(page, authorizationPath({ scopes: ['openid'], prompt: 'consent' }));
  await submitPassword(page, 'test@example.invalid');
  await assertTOTPPage(page, false);

  const loginRequests: Array<{ method: string; url: string }> = [];
  page.on('request', (request) => {
    if (request.url().includes('/mfa/webauthn/login/')) loginRequests.push({ method: request.method(), url: request.url() });
  });

  let failLoginBegin = true;
  browserErrors.allowHTTPError({ pathname: '/mfa/webauthn/login/begin', status: 503, count: 1 });
  await page.route('**/mfa/webauthn/login/begin?**', async (route) => {
    if (!failLoginBegin) {
      await route.continue();
      return;
    }
    failLoginBegin = false;
    await route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":"test outage"}' });
  });
  await submitTOTP(page, totp(secret, 0));
  await assertWebAuthnPage(page, 'login');
  await expect(page.locator('#webauthn-error')).toHaveText('Authentication failed (status 503)');
  await expect(page.getByRole('button', { name: 'Use Security Key' })).toBeVisible();
  await page.unroute('**/mfa/webauthn/login/begin?**');

  await authenticator.setPresence(false);
  await page.getByRole('button', { name: 'Use Security Key' }).click();
  await expect(page.locator('#webauthn-error')).toHaveText(
    'Request was cancelled or timed out. Please try again.',
    { timeout: 5_000 },
  );
  await expect(page.getByRole('button', { name: 'Use Security Key' })).toBeVisible();
  await authenticator.setPresence(true);

  const loginURL = page.url();
  const wrongLoginOrigin = new URL(loginURL);
  wrongLoginOrigin.hostname = '127.0.0.1';
  await page.goto(wrongLoginOrigin.href);
  await expect(page.locator('#webauthn-error')).toHaveText('Security key operation not allowed on this domain.');
  await expect(page.getByRole('button', { name: 'Use Security Key' })).toBeVisible();

  let releaseLogin!: () => void;
  const loginGate = new Promise<void>((resolve) => { releaseLogin = resolve; });
  await page.route('**/mfa/webauthn/login/begin?**', async (route) => {
    await loginGate;
    await route.continue();
  });
  await page.goto(loginURL);
  await assertWebAuthnPage(page, 'login');
  await expect(page.locator('#webauthn-working')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Use Security Key' })).toBeHidden();
  const approval = page.waitForURL(/\/approval\?/);
  releaseLogin();
  await approval;
  await page.unroute('**/mfa/webauthn/login/begin?**');
  assertWebAuthnRequests(loginRequests, 'login');
  await assertApproval(page, []);
});

test('device entry, invalid entry, success, home, and logout use real routes', async ({
  page,
  browserErrors,
  createVirtualAuthenticator,
}) => {
  test.setTimeout(30_000);
  locked('device.html', '<form method="post" action="{{ .PostURL }}">');
  locked('device.html', 'required id="user_code" name="user_code" type="text"');
  locked('device_success.html', 'Login Successful for {{ .ClientName }}');

  browserErrors.allowHTTPError({ pathname: '/device', status: 400, count: 1 });
  await page.goto('/device?user_code=BAD-CODE&invalid=true');
  await expect(page.getByRole('heading', { name: 'Enter User Code' })).toBeVisible();
  await expectAttributes(page.locator('#user_code'), {
    autocomplete: 'off', id: 'user_code', name: 'user_code', required: '', tabindex: '2', type: 'text',
  });
  await expect(page.locator('#user_code')).toHaveValue('BAD-CODE');
  await expect(page.locator('#user_code')).toBeFocused();
  await assertThemeMatrix(page);
  await expect(page.locator('#login-error')).toHaveText('Invalid or Expired User Code');
  await assertCriticalAxe(page, 'device');
  await expectAttributes(page.locator('form'), { action: '/device/auth/verify_code', method: 'post' });
  await expectAttributes(page.getByRole('button', { name: 'Submit' }), { id: 'submit-login', tabindex: '3', type: 'submit' });

  const deviceResponse = await page.request.post('/device/code', {
    form: {
      client_id: 'araihu-test', client_secret: 'local-test-client-secret', scope: 'openid profile',
    },
  });
  expect(deviceResponse.ok()).toBe(true);
  const device = await deviceResponse.json() as {
    user_code: string;
    verification_uri: string;
    verification_uri_complete: string;
  };
  expect(device.verification_uri).toBe(new URL('/device', baseURL()).href);
  await page.goto(device.verification_uri_complete);
  await expect(page.locator('#user_code')).toHaveValue(device.user_code);
  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.getByRole('heading', { name: 'Log in to AraiHu Dex' })).toBeVisible();
  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await enrollSimple(
    page,
    'device@example.invalid',
    '00000000-0000-4000-8000-000000000002',
    createVirtualAuthenticator,
  );
  await assertApproval(page, ['View basic profile information']);
  await page.getByRole('button', { name: 'Grant Access' }).click();
  await expect(page.getByRole('heading', { name: 'Login Successful for AraiHu Test Client' })).toBeVisible();
  await expect(page.getByText('Return to your device to continue')).toBeVisible();
  await assertCriticalAxe(page);
  await assertThemeMatrix(page);

  locked('home.html', '<a href="{{ .LogoutURL }}" class="dex-btn theme-btn--primary">Log out</a>');
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'device-user' })).toBeVisible();
  await assertCriticalAxe(page);
  await assertThemeMatrix(page);
  await expect(page.getByText('device@example.invalid')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Log out' })).toHaveAttribute('href', new URL('/logout', baseURL()).href);

  locked('logout.html', '<form method="post" action="{{ .ReqPath }}">');
  await page.goto('/logout');
  await expect(page.getByRole('heading', { name: 'Logging Out' })).toBeVisible();
  await assertCriticalAxe(page);
  await assertThemeMatrix(page);
  await expectAttributes(page.locator('form'), { action: '/logout', method: 'post' });
  await page.getByRole('button', { name: 'Log Out' }).click();
  await expect(page.getByRole('heading', { name: 'Logged Out' })).toBeVisible();
});

test('OOB and generic pages render through actual upstream handlers', async ({
  page,
  browserErrors,
  createVirtualAuthenticator,
}) => {
  test.setTimeout(30_000);
  await openPasswordWithAssertions(page, authorizationPath({
    redirectURI: 'urn:ietf:wg:oauth:2.0:oob', scopes: ['openid'], prompt: 'consent',
  }));
  await enrollSimple(
    page,
    'oob@example.invalid',
    '00000000-0000-4000-8000-000000000003',
    createVirtualAuthenticator,
  );
  await assertApproval(page, []);
  await page.getByRole('button', { name: 'Grant Access' }).click();
  locked('oob.html', '<input type="text" class="theme-form-input" value="{{ .Code }}" />');
  await expect(page.getByRole('heading', { name: 'Login Successful' })).toBeVisible();
  await assertThemeMatrix(page);
  const code = page.locator('input.theme-form-input');
  await expect(code).toHaveAttribute('type', 'text');
  await expect(code).toHaveValue(/\S+/);
  await assertCriticalAxe(page, 'oob');
  await expect(code).toHaveAccessibleName('');

  browserErrors.allowHTTPError({ pathname: '/auth', status: 400, count: 1 });
  const errorResponse = await page.goto('/auth');
  expect(errorResponse?.status()).toBe(400);
  locked('error.html', '<h2 class="theme-heading">{{ .ErrType }}</h2>');
  await expect(page.getByRole('heading', { name: 'Bad Request' })).toBeVisible();
  await assertCriticalAxe(page);
  await assertThemeMatrix(page);

  await page.context().clearCookies();
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Not signed in' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'OpenID configuration' })).toHaveAttribute(
    'href',
    new URL('/.well-known/openid-configuration', baseURL()).href,
  );
  await page.goto('/logout');
  await expect(page.getByRole('heading', { name: 'Session Not Found' })).toBeVisible();
});
