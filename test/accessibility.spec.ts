import AxeBuilder from '@axe-core/playwright';
import { assertCriticalAxe } from './fixtures/inherited-accessibility';
import { authorizationPath, expect, openAppearance, openPassword, test } from './fixtures/real-dex';
import { themes } from './fixtures/theme-matrix';

test('real Dex login has no critical accessibility violations', async ({ page }) => {
  await page.goto(authorizationPath());

  await assertCriticalAxe(page);
});

test('document exposes an English main landmark', async ({ page }) => {
  await page.goto(authorizationPath());

  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.getByRole('main')).toHaveCount(1);
});

test('native Dex logo stays legible in client-side dark mode', async ({ page }) => {
  await page.goto(authorizationPath());
  await openAppearance(page);
  await page.getByRole('button', { name: 'Switch to dark mode' }).click();

  await expect(page.locator('img.theme-navbar__logo')).toHaveCSS('filter', 'brightness(0) invert(1)');
});

test('appearance disclosure does not enlarge the 390px navbar', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(authorizationPath());

  const navbar = page.locator('.theme-navbar');
  const trigger = page.locator('.araihu-appearance-trigger');
  const theme = page.getByRole('combobox', { name: 'Theme' });
  await expect(trigger).toBeVisible();
  await expect(theme).toBeHidden();
  const closed = await navbar.boundingBox();
  expect(closed).not.toBeNull();
  expect(closed!.height).toBeLessThanOrEqual(64);

  await trigger.click();
  await expect(theme).toBeVisible();
  const [opened, controls] = await Promise.all([
    navbar.boundingBox(),
    page.locator('.araihu-appearance-controls').boundingBox(),
  ]);
  expect(opened).not.toBeNull();
  expect(controls).not.toBeNull();
  expect(Math.abs(opened!.height - closed!.height)).toBeLessThanOrEqual(1);
  expect(controls!.x).toBeGreaterThanOrEqual(16);
  expect(controls!.x + controls!.width).toBeLessThanOrEqual(374);
});

test('theme select reserves space for its own chevron', async ({ page }) => {
  await page.goto(authorizationPath());
  await openAppearance(page);

  const select = page.getByRole('combobox', { name: 'Theme' });
  await expect(select.locator('..')).toHaveClass('araihu-theme-select');
  const style = await select.evaluate((element) => {
    const computed = getComputedStyle(element);
    return {
      appearance: computed.appearance,
      paddingRight: Number.parseFloat(computed.paddingRight),
    };
  });
  expect(style.appearance).toBe('none');
  expect(style.paddingRight).toBeGreaterThanOrEqual(32);
});

test('authentication and consent share one compact width rhythm', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(authorizationPath());

  const [panel, notice, provider] = await Promise.all([
    page.locator('.theme-panel').boundingBox(),
    page.getByRole('complementary', { name: 'Appearance preferences' }).boundingBox(),
    page.getByRole('link', { name: 'Log in with Email' }).boundingBox(),
  ]);
  expect(panel).not.toBeNull();
  expect(notice).not.toBeNull();
  expect(provider).not.toBeNull();
  expect(Math.abs(panel!.width - notice!.width)).toBeLessThanOrEqual(1);
  expect(provider!.height).toBeLessThanOrEqual(48);
});

test('upstream form geometry aligns with Goshtoso controls and body type', async ({ page }) => {
  await openPassword(page);
  await openAppearance(page);

  const select = page.getByRole('combobox', { name: 'Theme' });
  for (const theme of themes) {
    await select.selectOption(theme);
    const geometry = await page.evaluate(() => {
      const labelWrap = document.querySelector<HTMLElement>('.theme-form-label');
      const label = document.querySelector<HTMLElement>('.theme-form-label > label');
      const input = document.querySelector<HTMLElement>('.theme-form-input');
      const remember = document.querySelector<HTMLElement>('.theme-remember-me');
      if (!labelWrap || !label || !input || !remember) throw new Error('password geometry missing');
      return {
        input: input.getBoundingClientRect().toJSON(),
        label: label.getBoundingClientRect().toJSON(),
        labelWrap: labelWrap.getBoundingClientRect().toJSON(),
        remember: remember.getBoundingClientRect().toJSON(),
        rememberJustify: getComputedStyle(remember).justifyContent,
      };
    });
    expect(Math.abs(geometry.label.x - geometry.input.x), `${theme} label x`).toBeLessThanOrEqual(1);
    expect(Math.abs(geometry.labelWrap.width - geometry.input.width), `${theme} label width`).toBeLessThanOrEqual(1);
    expect(Math.abs(geometry.remember.x - geometry.input.x), `${theme} remember x`).toBeLessThanOrEqual(1);
    expect(geometry.rememberJustify, `${theme} remember alignment`).toBe('flex-start');
  }

  const fonts = await page.evaluate(() => ({
    body: getComputedStyle(document.body).fontFamily,
    token: getComputedStyle(document.documentElement).getPropertyValue('--font-body').trim(),
  }));
  expect(fonts.token).not.toBe('');
  expect(fonts.body.replaceAll('"', '')).toBe(fonts.token.replaceAll('"', ''));
});

test('dismissing storage notice returns focus to the upstream login field', async ({ page }) => {
  await page.goto(authorizationPath());
  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await expect(page.locator('#login')).toBeFocused();

  await page.getByRole('button', { name: 'Not now' }).click();

  await expect(page.getByLabel('Appearance preferences')).toBeHidden();
  await expect(page.locator('#login')).toBeFocused();
});

test('real device entry locks its inherited critical label violation to upstream bytes', async ({ page, browserErrors }) => {
  browserErrors.allowHTTPError({ pathname: '/device', status: 400, count: 1 });
  await page.goto('/device?user_code=BAD-CODE&invalid=true');

  await assertCriticalAxe(page, 'device');
  await expect(page.locator('#user_code')).toHaveAccessibleName('');
});

test('overlay controls and upstream password fields expose names, roles, and states', async ({ page }) => {
  await page.goto(authorizationPath());
  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await openAppearance(page);

  await expect(page.getByRole('combobox', { name: 'Theme' })).toHaveValue('araihu');
  await expect(page.getByRole('button', { name: 'Switch to dark mode' })).toHaveAttribute('aria-pressed', 'false');
  await expect(page.getByRole('complementary', { name: 'Appearance preferences' })).toBeVisible();
  await expect(page.getByRole('textbox', { name: 'Email Address' })).toHaveAttribute('required', '');
  await expect(page.getByLabel('Password')).toHaveAttribute('type', 'password');
  await expect(page.getByRole('checkbox', { name: 'Remember me' })).toBeChecked();
  await expect(page.getByRole('button', { name: 'Login' })).toHaveAttribute('type', 'submit');

  const select = page.getByRole('combobox', { name: 'Theme' });
  await select.focus();
  await select.press('9');
  await expect(page.locator('html')).toHaveAttribute('data-theme', '90s');

  const mode = page.locator('.araihu-mode-button');
  await mode.focus();
  await mode.press('Enter');
  await expect(page.locator('html')).toHaveClass(/\bdark\b/);
  await expect(mode).toHaveAttribute('aria-label', 'Switch to light mode');
  await expect(mode).toHaveAttribute('aria-pressed', 'true');
  await mode.click();
  await expect(page.locator('html')).not.toHaveClass(/\bdark\b/);
  await expect(mode).toHaveAttribute('aria-label', 'Switch to dark mode');
});

test('keyboard focus is visible on overlay and authentication controls', async ({ page }) => {
  await page.goto(authorizationPath());
  await page.getByRole('link', { name: 'Log in with Email' }).click();
  await openAppearance(page);

  const controls = [
    ['appearance', page.locator('.araihu-appearance-trigger')],
    ['theme', page.getByRole('combobox', { name: 'Theme' })],
    ['mode', page.locator('.araihu-mode-button')],
    ['email', page.getByLabel('Email Address')],
    ['password', page.getByLabel('Password')],
    ['remember', page.getByRole('checkbox', { name: 'Remember me' })],
    ['login', page.getByRole('button', { name: 'Login' })],
    ['allow', page.getByRole('button', { name: 'Save', exact: true })],
    ['deny', page.getByRole('button', { name: 'Not now' })],
  ] as const;
  const focusResults = [];
  for (const [name, control] of controls) {
    await control.focus();
    await page.keyboard.press('Shift+Tab');
    await page.keyboard.press('Tab');
    await expect(control).toBeFocused();
    const focus = await control.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        visible: element.matches(':focus-visible'),
        color: style.outlineColor,
        style: style.outlineStyle,
        width: Number.parseFloat(style.outlineWidth),
      };
    });
    focusResults.push({ name, ...focus });
  }
  expect(focusResults.filter(({ visible, style, width, color }) => (
    !visible || style === 'none' || width < 3 || color === 'rgba(0, 0, 0, 0)'
  ))).toEqual([]);
});

test('390px layout has no horizontal clipping or consent obstruction', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(authorizationPath());
  await page.getByRole('link', { name: 'Log in with Email' }).click();

  const submit = page.getByRole('button', { name: 'Login' });
  const notice = page.getByRole('complementary', { name: 'Appearance preferences' });
  const navbar = page.locator('.theme-navbar');
  await expect(submit).toBeVisible();
  await expect(notice).toBeVisible();
  await expect(navbar).toBeVisible();
  const [submitBox, noticeBox] = await Promise.all([submit.boundingBox(), notice.boundingBox()]);
  expect(submitBox).not.toBeNull();
  expect(noticeBox).not.toBeNull();

  const layout = await page.evaluate(() => {
    const navbarElement = document.querySelector('.theme-navbar')!;
    const navbarRect = navbarElement.getBoundingClientRect();
    const navbarClipping = Array.from(navbarElement.children).flatMap((element) => {
      const rect = element.getBoundingClientRect();
      return rect.top < navbarRect.top - 0.5 || rect.bottom > navbarRect.bottom + 0.5
        ? [{ selector: element.className, top: rect.top, bottom: rect.bottom, navbarBottom: navbarRect.bottom }]
        : [];
    });
    const visibleOverflow = Array.from(document.body.querySelectorAll('*')).flatMap((element) => {
      const rect = element.getBoundingClientRect();
      if (!rect.width || !rect.height || getComputedStyle(element).position === 'fixed') return [];
      return rect.left < -0.5 || rect.right > window.innerWidth + 0.5
        ? [{ selector: element.tagName.toLowerCase(), left: rect.left, right: rect.right }]
        : [];
    });
    return {
      documentWidth: document.documentElement.scrollWidth,
      viewportWidth: window.innerWidth,
      visibleOverflow,
      navbarClipping,
    };
  });
  const overlaps = !(
    submitBox!.x + submitBox!.width <= noticeBox!.x
    || submitBox!.x >= noticeBox!.x + noticeBox!.width
    || submitBox!.y + submitBox!.height <= noticeBox!.y
    || submitBox!.y >= noticeBox!.y + noticeBox!.height
  );
  expect(layout.documentWidth).toBeLessThanOrEqual(layout.viewportWidth);
  expect(layout.visibleOverflow).toEqual([]);
  expect(layout.navbarClipping).toEqual([]);
  expect(overlaps).toBe(false);
});

test('reduced motion disables transitions and animations', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto(authorizationPath());
  await page.getByRole('link', { name: 'Log in with Email' }).click();

  const moving = await page.locator('body, body *').evaluateAll((elements) => elements.flatMap((element) => {
    const style = getComputedStyle(element);
    const hasDuration = (value: string) => value.split(',').some((part) => Number.parseFloat(part) > 0);
    return hasDuration(style.animationDuration) || hasDuration(style.transitionDuration)
      ? [{ tag: element.tagName, animation: style.animationDuration, transition: style.transitionDuration }]
      : [];
  }));
  expect(moving).toEqual([]);
  await expect(page.locator('html')).toHaveCSS('scroll-behavior', 'auto');
});

test('every allowlisted login theme has Axe-verified text and control contrast', async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto(authorizationPath());
  await openAppearance(page);
  const select = page.getByRole('combobox', { name: 'Theme' });
  const mode = page.locator('.araihu-mode-button');
  const failures = [];

  for (const theme of themes) {
    await select.selectOption(theme);
    if (await page.locator('html').evaluate((root) => root.classList.contains('dark'))) await mode.click();
    for (const colorMode of ['light', 'dark'] as const) {
      if (colorMode === 'dark') await mode.click();
      const { violations } = await new AxeBuilder({ page }).withRules(['color-contrast']).analyze();
      for (const violation of violations) {
        for (const node of violation.nodes) {
          failures.push({
            theme,
            mode: colorMode,
            rule: violation.id,
            target: node.target.join(' '),
            detail: node.any.map(({ data }) => data),
          });
        }
      }
    }
  }
  expect(failures).toEqual([]);
});
