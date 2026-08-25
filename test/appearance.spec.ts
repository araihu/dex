import { expect, test, type Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';

const origin = 'http://dex.test';
const loginURL = `${origin}/auth/local`;
const appearance = await readFile(new URL('../web/static/appearance.js', import.meta.url), 'utf8');

const options = `
  <option value="90s">90s</option>
  <option value="araihu">Arai Hû</option>
  <option value="arctic">Arctic</option>
  <option value="christmas">Christmas</option>
  <option value="dracula">Dracula</option>
  <option value="goshtoso">Goshtoso</option>
  <option value="halloween">Halloween</option>
  <option value="high-contrast">High Contrast</option>
  <option value="industrial">Industrial</option>
  <option value="minimal">Minimal</option>
  <option value="modern">Modern</option>
  <option value="neo-brutalism">Neo Brutalism</option>
  <option value="news">News</option>
  <option value="pastel">Pastel</option>
  <option value="prototype">Prototype</option>
  <option value="zombie">Zombie</option>`;

async function serveFixture(page: Page, runtimeDefault = 'araihu') {
  await page.route(`${origin}/**`, async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname === '/static/appearance.js') {
      await route.fulfill({ contentType: 'application/javascript', body: appearance });
      return;
    }
    await route.fulfill({
      contentType: 'text/html',
      body: `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <script>window.__araihuDexDefaultTheme = ${JSON.stringify(runtimeDefault)}</script>
    <script defer src="/static/appearance.js"></script>
  </head>
  <body>
    <label for="araihu-theme">Tema</label>
    <select id="araihu-theme" aria-label="Tema">${options}</select>
    <button class="araihu-mode-button" type="button" aria-label="Ativar modo escuro" aria-pressed="false">Modo</button>
    <form method="post" action="/auth/local"><input name="login"><button>Entrar</button></form>
    <aside id="araihu-storage-notice" aria-label="Preferências de aparência">
      <button type="button" data-storage-choice="allowed">Permitir</button>
      <button type="button" data-storage-choice="denied">Não permitir</button>
    </aside>
  </body>
</html>`,
    });
  });
}

async function seedStorage(page: Page, values: Record<string, string>) {
  await page.goto(`${origin}/seed`);
  await page.evaluate((entries) => {
    for (const [key, value] of Object.entries(entries)) localStorage.setItem(key, value);
  }, values);
}

test('denied storage changes only the current page', async ({ page }) => {
  await serveFixture(page);
  await page.context().addCookies([{ name: 'gt_storage', value: 'denied', url: origin }]);

  await page.goto(loginURL);
  await page.getByLabel('Tema').selectOption('dracula');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dracula');
  await page.reload();

  await expect(page.locator('html')).toHaveAttribute('data-theme', 'araihu');
});

test('allowed storage restores valid preferences ahead of runtime and media defaults', async ({ page }) => {
  await serveFixture(page, 'modern');
  await page.emulateMedia({ colorScheme: 'light' });
  await page.context().addCookies([{ name: 'gt_storage', value: 'allowed', url: origin }]);
  await seedStorage(page, { theme: 'dracula', darkMode: 'true' });

  await page.goto(loginURL);

  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dracula');
  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await expect(page.getByLabel('Tema')).toHaveValue('dracula');
  await expect(page.getByRole('button', { name: 'Ativar modo claro' })).toHaveAttribute('aria-pressed', 'true');
});

test('invalid stored and runtime themes fall back through the actual options', async ({ page }) => {
  await serveFixture(page, 'UNKNOWN');
  await page.context().addCookies([{ name: 'gt_storage', value: 'allowed', url: origin }]);
  await seedStorage(page, { theme: 'not-an-option' });

  await page.goto(loginURL);

  await expect(page.locator('html')).toHaveAttribute('data-theme', 'araihu');
  await expect(page.getByLabel('Tema')).toHaveValue('araihu');
});

test('malformed stored dark mode falls back to the system preference', async ({ page }) => {
  await serveFixture(page);
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.context().addCookies([{ name: 'gt_storage', value: 'allowed', url: origin }]);
  await seedStorage(page, { darkMode: 'sometimes' });

  await page.goto(loginURL);

  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await expect(page.getByRole('button', { name: 'Ativar modo claro' })).toHaveAttribute('aria-pressed', 'true');
});

test('without an allowed preference runtime theme and system dark mode win', async ({ page }) => {
  await serveFixture(page, 'christmas');
  await page.emulateMedia({ colorScheme: 'dark' });

  await page.goto(loginURL);

  await expect(page.locator('html')).toHaveAttribute('data-theme', 'christmas');
  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await expect(page.getByLabel('Preferências de aparência')).toBeVisible();
});

test('allow writes the host cookie and only appearance preferences', async ({ page }) => {
  await serveFixture(page);
  await page.goto(loginURL);
  await page.getByLabel('Tema').selectOption('pastel');
  await page.getByRole('button', { name: 'Ativar modo escuro' }).click();
  await page.getByRole('button', { name: 'Permitir', exact: true }).click();

  const cookie = (await page.context().cookies(origin)).find(({ name }) => name === 'gt_storage');
  expect(cookie).toMatchObject({ value: 'allowed', path: '/', sameSite: 'Lax' });
  expect(cookie!.expires - Date.now() / 1000).toBeGreaterThan(15_551_900);
  expect(cookie!.expires - Date.now() / 1000).toBeLessThanOrEqual(15_552_000);
  await expect(page.getByLabel('Preferências de aparência')).toBeHidden();
  expect(await page.evaluate(() => ({
    theme: localStorage.getItem('theme'),
    darkMode: localStorage.getItem('darkMode'),
    keys: Object.keys(localStorage).sort(),
  }))).toEqual({ theme: 'pastel', darkMode: 'true', keys: ['darkMode', 'theme'] });
});

test('deny removes only overlay appearance keys', async ({ page }) => {
  await serveFixture(page);
  await seedStorage(page, { theme: 'dracula', darkMode: 'true', unrelated: 'keep' });
  await page.goto(loginURL);

  await page.getByRole('button', { name: 'Não permitir' }).click();

  expect(await page.evaluate(() => ({
    theme: localStorage.getItem('theme'),
    darkMode: localStorage.getItem('darkMode'),
    unrelated: localStorage.getItem('unrelated'),
  }))).toEqual({ theme: null, darkMode: null, unrelated: 'keep' });
  const cookie = (await page.context().cookies(origin)).find(({ name }) => name === 'gt_storage');
  expect(cookie).toMatchObject({ value: 'denied', path: '/', sameSite: 'Lax' });
});

test('storage exceptions keep login and in-memory appearance usable', async ({ page }) => {
  await serveFixture(page);
  await page.context().addCookies([{ name: 'gt_storage', value: 'allowed', url: origin }]);
  await page.addInitScript(() => {
    Object.defineProperty(window, 'localStorage', {
      value: {
        getItem() { throw new DOMException('blocked', 'SecurityError'); },
        setItem() { throw new DOMException('blocked', 'SecurityError'); },
        removeItem() { throw new DOMException('blocked', 'SecurityError'); },
      },
    });
  });
  const errors: Error[] = [];
  page.on('pageerror', (error) => errors.push(error));

  await page.goto(loginURL);
  await page.getByLabel('Tema').selectOption('dracula');
  await page.getByRole('button', { name: 'Ativar modo escuro' }).click();

  await expect(page.locator('form')).toBeVisible();
  await expect(page).toHaveURL(/\/auth\/local/);
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dracula');
  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await page.evaluate(() => {
    document.cookie = 'gt_storage=denied; Path=/; Max-Age=15552000; SameSite=Lax';
  });
  await page.reload();
  await expect(page.locator('form')).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'araihu');
  expect(errors).toEqual([]);
});

test('cookie exceptions keep controls usable and errors contained', async ({ page }) => {
  await serveFixture(page);
  await page.emulateMedia({ colorScheme: 'light' });
  await page.addInitScript(() => {
    Object.defineProperty(Document.prototype, 'cookie', {
      configurable: true,
      get() { throw new DOMException('blocked', 'SecurityError'); },
      set() { throw new DOMException('blocked', 'SecurityError'); },
    });
  });
  const errors: Error[] = [];
  page.on('pageerror', (error) => errors.push(error));

  await page.goto(loginURL);
  await page.getByRole('button', { name: 'Permitir', exact: true }).click();
  await page.getByLabel('Tema').selectOption('zombie');
  await page.getByRole('button', { name: 'Ativar modo escuro' }).click();

  await expect(page.locator('form')).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'zombie');
  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await expect(page.getByLabel('Preferências de aparência')).toBeVisible();
  expect(await page.evaluate(() => ({
    theme: localStorage.getItem('theme'),
    darkMode: localStorage.getItem('darkMode'),
  }))).toEqual({ theme: null, darkMode: null });
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'araihu');
  await expect(page.locator('html')).not.toHaveClass(/\bdark\b/);
  await expect(page.getByRole('button', { name: 'Ativar modo escuro' })).toHaveAttribute('aria-pressed', 'false');
  expect(errors).toEqual([]);
});

test('native controls update accessible state without touching the login form', async ({ page }) => {
  await serveFixture(page);
  await page.goto(loginURL);
  const formBefore = await page.locator('form').evaluate((form) => ({
    action: form.getAttribute('action'),
    method: form.getAttribute('method'),
    html: form.innerHTML,
  }));

  await page.getByLabel('Tema').focus();
  await page.getByLabel('Tema').selectOption('neo-brutalism');
  await page.getByRole('button', { name: 'Ativar modo escuro' }).press('Enter');

  await expect(page.locator('html')).toHaveAttribute('data-theme', 'neo-brutalism');
  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await expect(page.getByRole('button', { name: 'Ativar modo claro' })).toHaveAttribute('aria-pressed', 'true');
  expect(await page.locator('form').evaluate((form) => ({
    action: form.getAttribute('action'),
    method: form.getAttribute('method'),
    html: form.innerHTML,
  }))).toEqual(formBefore);
  await expect(page).toHaveURL(loginURL);
});
