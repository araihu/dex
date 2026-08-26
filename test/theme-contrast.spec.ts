import AxeBuilder from '@axe-core/playwright';
import {
  authorizationPath,
  expect,
  openAppearance,
  openPassword,
  readTOTPSecret,
  submitPassword,
  submitTOTP,
  test,
  totp,
} from './fixtures/real-dex';
import { themes } from './fixtures/theme-matrix';

const formerlyFailingPrimaryPairs = [
  ['araihu', 'light'],
  ['araihu', 'dark'],
  ['arctic', 'light'],
  ['dracula', 'light'],
  ['goshtoso', 'light'],
  ['goshtoso', 'dark'],
  ['halloween', 'light'],
  ['high-contrast', 'light'],
  ['high-contrast', 'dark'],
  ['pastel', 'light'],
  ['zombie', 'light'],
  ['zombie', 'dark'],
] as const;

const formerlyFailingErrorPairs = [
  ['araihu', 'light'],
  ['araihu', 'dark'],
  ['arctic', 'dark'],
  ['christmas', 'light'],
  ['christmas', 'dark'],
  ['dracula', 'light'],
  ['dracula', 'dark'],
  ['goshtoso', 'light'],
  ['goshtoso', 'dark'],
  ['halloween', 'light'],
  ['halloween', 'dark'],
  ['high-contrast', 'light'],
  ['high-contrast', 'dark'],
  ['industrial', 'dark'],
  ['news', 'dark'],
  ['pastel', 'light'],
  ['zombie', 'light'],
  ['zombie', 'dark'],
] as const;

test('appearance controls use contrast-safe strong tokens for boundaries and focus', async ({ page }) => {
  await page.goto(authorizationPath());
  await openAppearance(page);
  const root = page.locator('html');
  const select = page.getByLabel('Theme');
  const modeButton = page.locator('.araihu-mode-button');
  const failures = [];

  for (const theme of themes) {
    await select.selectOption(theme);
    if (await root.evaluate((element) => element.classList.contains('dark'))) await modeButton.click();
    for (const mode of ['light', 'dark'] as const) {
      if (mode === 'dark') await modeButton.click();
      await select.focus();
      const colors = await select.evaluate((element, dark) => {
        const control = getComputedStyle(element);
        const probe = document.createElement('span');
        probe.style.color = `var(${dark ? '--color-on-surface-dark-strong' : '--color-on-surface-strong'})`;
        document.body.append(probe);
        const expected = getComputedStyle(probe).color;
        probe.remove();
        return {
          boundary: control.borderTopColor,
          focus: control.outlineColor,
          expected,
        };
      }, mode === 'dark');
      if (colors.boundary !== colors.expected || colors.focus !== colors.expected) {
        failures.push({ theme, mode, ...colors });
      }
    }
  }

  expect(failures).toEqual([]);
});

test('primary buttons use the approved contrast-safe token pair in every formerly failing mode', async ({ page }) => {
  await openPassword(page);
  const root = page.locator('html');
  const modeButton = page.locator('.araihu-mode-button');
  const primary = page.locator('#submit-login');
  await openAppearance(page);

  for (const [theme, mode] of formerlyFailingPrimaryPairs) {
    await page.getByLabel('Theme').selectOption(theme);
    const wantsDark = mode === 'dark';
    if (await root.evaluate((element) => element.classList.contains('dark')) !== wantsDark) {
      await modeButton.click();
    }
    const expected = await root.evaluate((_, dark) => {
      const resolve = (name: string) => {
        const probe = document.createElement('span');
        probe.style.color = `var(${name})`;
        document.body.append(probe);
        const color = getComputedStyle(probe).color;
        probe.remove();
        return color;
      };
      return {
        background: resolve(dark ? '--color-on-surface-dark-strong' : '--color-on-surface-strong'),
        border: resolve(dark ? '--color-on-surface-dark-strong' : '--color-on-surface-strong'),
        text: resolve(dark ? '--color-surface-dark' : '--color-surface'),
      };
    }, wantsDark);
    await expect(primary, `${theme}/${mode} primary background`).toHaveCSS('background-color', expected.background);
    await expect(primary, `${theme}/${mode} primary border`).toHaveCSS('border-color', expected.border);
    await expect(primary, `${theme}/${mode} primary text`).toHaveCSS('color', expected.text);
    const { violations } = await new AxeBuilder({ page })
      .include('#submit-login')
      .withRules(['color-contrast'])
      .analyze();
    expect(violations, `${theme}/${mode} primary contrast`).toEqual([]);
  }
});

test('error boxes retain danger tokens on a surface in every formerly failing mode', async ({
  page,
  browserErrors,
}) => {
  await openPassword(page);
  browserErrors.allowHTTPError({ pathname: '/auth/local/login', status: 401, count: 1 });
  await submitPassword(page, 'test@example.invalid', 'wrong-password');
  const root = page.locator('html');
  const modeButton = page.locator('.araihu-mode-button');
  const errorBox = page.locator('#login-error');
  await openAppearance(page);

  for (const [theme, mode] of formerlyFailingErrorPairs) {
    await page.getByLabel('Theme').selectOption(theme);
    const wantsDark = mode === 'dark';
    if (await root.evaluate((element) => element.classList.contains('dark')) !== wantsDark) {
      await modeButton.click();
    }
    const expected = await root.evaluate((_, dark) => {
      const resolve = (name: string) => {
        const probe = document.createElement('span');
        probe.style.color = `var(${name})`;
        document.body.append(probe);
        const color = getComputedStyle(probe).color;
        probe.remove();
        return color;
      };
      return {
        background: resolve(dark ? '--color-surface-dark' : '--color-surface'),
        border: resolve('--color-danger'),
        text: resolve(dark ? '--color-danger-text-dark' : '--color-danger-text'),
      };
    }, wantsDark);
    await expect(errorBox, `${theme}/${mode} error background`).toHaveCSS('background-color', expected.background);
    await expect(errorBox, `${theme}/${mode} error border`).toHaveCSS('border-color', expected.border);
    await expect(errorBox, `${theme}/${mode} error text`).toHaveCSS('color', expected.text);
    const { violations } = await new AxeBuilder({ page })
      .include('#login-error')
      .withRules(['color-contrast'])
      .analyze();
    expect(violations, `${theme}/${mode} error contrast`).toEqual([]);
  }
});

test('home uses upstream theme hooks bound to contrast-safe tokens in the full matrix', async ({ page }) => {
  await page.goto('/');
  const root = page.locator('html');
  const home = page.locator('.dex-home');
  const modeButton = page.locator('.araihu-mode-button');
  await openAppearance(page);

  for (const theme of themes) {
    await page.getByLabel('Theme').selectOption(theme);
    if (await root.evaluate((element) => element.classList.contains('dark'))) await modeButton.click();
    for (const mode of ['light', 'dark'] as const) {
      if (mode === 'dark') await modeButton.click();
      const colors = await home.evaluate((element, dark) => {
        const resolve = (name: string) => {
          const probe = document.createElement('span');
          probe.style.color = `var(${name})`;
          element.append(probe);
          const color = getComputedStyle(probe).color;
          probe.remove();
          return color;
        };
        return {
          actual: {
            accent: resolve('--dex-home-accent'),
            border: resolve('--dex-home-border'),
            foreground: resolve('--dex-home-fg'),
            muted: resolve('--dex-home-muted'),
          },
          expected: {
            accent: resolve(dark ? '--color-on-surface-dark-strong' : '--color-on-surface-strong'),
            border: resolve(dark ? '--color-outline-dark' : '--color-outline'),
            foreground: resolve(dark ? '--color-on-surface-dark-strong' : '--color-on-surface-strong'),
            muted: resolve(dark ? '--color-on-surface-dark' : '--color-on-surface'),
          },
        };
      }, mode === 'dark');
      expect(colors.actual, `${theme}/${mode} home token hooks`).toEqual(colors.expected);
    }
  }
});

test('approval subtle text, scope list, and success action use approved pairs in the full matrix', async ({
  page,
  createVirtualAuthenticator,
}) => {
  test.setTimeout(60_000);
  await openPassword(page, authorizationPath({ scopes: ['openid', 'profile', 'email'] }));
  await submitPassword(page, 'contrast@example.invalid');
  const secret = readTOTPSecret('00000000-0000-4000-8000-000000000007');
  await submitTOTP(page, totp(secret, -1));
  await createVirtualAuthenticator();
  await Promise.all([
    page.waitForURL(/\/approval\?/),
    page.getByRole('button', { name: 'Register Security Key' }).click(),
  ]);

  const root = page.locator('html');
  const modeButton = page.locator('.araihu-mode-button');
  const subtle = page.locator('.dex-subtle-text');
  const list = page.locator('.dex-list');
  const success = page.locator('.theme-btn--success');
  await openAppearance(page);
  for (const theme of themes) {
    await page.getByLabel('Theme').selectOption(theme);
    if (await root.evaluate((element) => element.classList.contains('dark'))) await modeButton.click();
    for (const mode of ['light', 'dark'] as const) {
      if (mode === 'dark') await modeButton.click();
      const expected = await root.evaluate((_, dark) => {
        const resolve = (name: string) => {
          const probe = document.createElement('span');
          probe.style.color = `var(${name})`;
          document.body.append(probe);
          const color = getComputedStyle(probe).color;
          probe.remove();
          return color;
        };
        return {
          strong: resolve(dark ? '--color-on-surface-dark-strong' : '--color-on-surface-strong'),
          successBorder: resolve(dark ? '--color-success-action-dark' : '--color-success-action'),
          surface: resolve(dark ? '--color-surface-dark' : '--color-surface'),
        };
      }, mode === 'dark');
      await expect(subtle, `${theme}/${mode} subtle text`).toHaveCSS('color', expected.strong);
      await expect(list, `${theme}/${mode} scope list`).toHaveCSS('color', expected.strong);
      await expect(success, `${theme}/${mode} success background`).toHaveCSS('background-color', expected.strong);
      await expect(success, `${theme}/${mode} success border`).toHaveCSS('border-color', expected.successBorder);
      await expect(success, `${theme}/${mode} success text`).toHaveCSS('color', expected.surface);
      const { violations } = await new AxeBuilder({ page })
        .include('.theme-panel')
        .withRules(['color-contrast'])
        .analyze();
      expect(violations, `${theme}/${mode} approval contrast`).toEqual([]);
    }
  }
});

test('page-specific contrast matrix rejects a low-contrast mutation in every mode', async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto(authorizationPath());
  await page.locator('.dex-container').evaluate((container) => {
    const mutation = document.createElement('p');
    mutation.id = 'contrast-mutation';
    mutation.style.color = 'rgb(200, 200, 200)';
    mutation.style.backgroundColor = 'rgb(255, 255, 255)';
    mutation.textContent = 'This unrelated page-specific regression must fail.';
    container.append(mutation);
  });
  await expect(page.locator('#contrast-mutation')).toBeVisible();
  await expect(page.locator('#contrast-mutation')).toHaveCSS('color', 'rgb(200, 200, 200)');
  await expect(page.locator('#contrast-mutation')).toHaveCSS('background-color', 'rgb(255, 255, 255)');

  const matrix = await import('./fixtures/theme-matrix') as unknown as Record<string, unknown>;
  const assertThemeContrastMatrix = matrix.assertThemeContrastMatrix;
  expect(typeof assertThemeContrastMatrix).toBe('function');
  if (typeof assertThemeContrastMatrix !== 'function') return;

  let failure: unknown;
  try {
    await (assertThemeContrastMatrix as (page: typeof page, state: string) => Promise<void>)(
      page,
      'contrast-mutation',
    );
  } catch (error) {
    failure = error;
  }
  expect(failure).toBeInstanceOf(Error);
  expect((failure as Error).message).toContain('color-contrast');
  expect((failure as Error).message).toContain('#contrast-mutation');
});
