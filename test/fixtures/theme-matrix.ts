import { readFile } from 'node:fs/promises';
import AxeBuilder from '@axe-core/playwright';
import { expect, type Page } from '@playwright/test';
import { closeAppearance, openAppearance } from './real-dex';

const exactThemeKeys = [
  '90s',
  'araihu',
  'arctic',
  'christmas',
  'dracula',
  'goshtoso',
  'halloween',
  'high-contrast',
  'industrial',
  'minimal',
  'modern',
  'neo-brutalism',
  'news',
  'pastel',
  'prototype',
  'zombie',
] as const;

export function assertExactThemeCatalog(candidate: readonly string[]) {
  if (candidate.length !== exactThemeKeys.length
    || candidate.some((key, index) => key !== exactThemeKeys[index])) {
    throw new Error('theme catalog must match the exact 16-key order');
  }
}

const allowlistedThemes = (await readFile(
  new URL('../../web/static/theme-allowlist.txt', import.meta.url),
  'utf8',
)).trim().split('\n').map((line) => line.split('\t')[0]);
assertExactThemeCatalog(allowlistedThemes);
export const themes = allowlistedThemes;

async function waitForThemeTransitions(page: Page) {
  await page.evaluate(async () => {
    await new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
    const transitions = document.getAnimations().filter((animation) => (
      animation.constructor.name === 'CSSTransition'
    ));
    await Promise.all(transitions.map((animation) => animation.finished.catch(() => undefined)));
  });
}

export async function assertThemeContrastMatrix(page: Page, state: string) {
  await openAppearance(page);
  const select = page.getByLabel('Theme');
  const modeButton = page.locator('.araihu-mode-button');
  const root = page.locator('html');
  const failures: Array<{
    state: string;
    theme: string;
    mode: 'light' | 'dark';
    rule: string;
    target: string;
    detail: unknown;
  }> = [];

  for (const theme of themes) {
    await select.selectOption(theme);
    if (await root.evaluate((element) => element.classList.contains('dark'))) await modeButton.click();
    for (const mode of ['light', 'dark'] as const) {
      if (mode === 'dark') await modeButton.click();
      await expect(root, `${state} ${theme}/${mode} root theme`).toHaveAttribute('data-theme', theme);
      if (mode === 'dark') {
        await expect(root, `${state} ${theme}/${mode} root mode`).toHaveClass(/\bdark\b/);
      } else {
        await expect(root, `${state} ${theme}/${mode} root mode`).not.toHaveClass(/\bdark\b/);
      }
      await waitForThemeTransitions(page);
      const { violations } = await new AxeBuilder({ page }).withRules(['color-contrast']).analyze();
      for (const violation of violations) {
        for (const node of violation.nodes) {
          failures.push({
            state,
            theme,
            mode,
            rule: violation.id,
            target: node.target.join(' '),
            detail: node.any[0]?.data,
          });
        }
      }
    }
  }

  await select.selectOption('araihu');
  if (await root.evaluate((element) => element.classList.contains('dark'))) await modeButton.click();
  await closeAppearance(page);
  if (failures.length) {
    throw new Error(`color-contrast failures: ${JSON.stringify(failures)}`);
  }
}

type ThemeSample = {
  theme: string;
  mode: 'light' | 'dark';
  rootTheme: string | undefined;
  rootMode: boolean;
  variables: Record<string, string>;
  body: { background: string; color: string };
  panel: { background: string; color: string };
  control: { background: string; border: string; color: string };
};

const semanticVariables = [
  '--color-surface',
  '--color-surface-alt',
  '--color-on-surface',
  '--color-on-surface-strong',
  '--color-primary',
  '--color-on-primary',
  '--color-surface-dark',
  '--color-surface-dark-alt',
  '--color-on-surface-dark',
  '--color-on-surface-dark-strong',
  '--color-primary-dark',
  '--color-on-primary-dark',
] as const;

async function sample(page: Page, theme: string, mode: 'light' | 'dark'): Promise<ThemeSample> {
  return page.evaluate(({ expectedTheme, expectedMode, variableNames }) => {
    const root = document.documentElement;
    const rootStyle = getComputedStyle(root);
    const bodyStyle = getComputedStyle(document.body);
    const panelStyle = getComputedStyle(document.querySelector('.theme-panel')!);
    const controlStyle = getComputedStyle(document.querySelector('#araihu-theme')!);
    return {
      theme: expectedTheme,
      mode: expectedMode,
      rootTheme: root.dataset.theme,
      rootMode: root.classList.contains('dark'),
      variables: Object.fromEntries(variableNames.map((name) => [name, rootStyle.getPropertyValue(name).trim()])),
      body: { background: bodyStyle.backgroundColor, color: bodyStyle.color },
      panel: { background: panelStyle.backgroundColor, color: panelStyle.color },
      control: {
        background: controlStyle.backgroundColor,
        border: controlStyle.borderColor,
        color: controlStyle.color,
      },
    };
  }, { expectedTheme: theme, expectedMode: mode, variableNames: semanticVariables });
}

export async function assertThemeMatrix(page: Page) {
  await openAppearance(page);
  const select = page.getByLabel('Theme');
  const modeButton = page.locator('.araihu-mode-button');
  const samples: ThemeSample[] = [];

  for (const theme of themes) {
    await select.selectOption(theme);
    if (await page.locator('html').evaluate((root) => root.classList.contains('dark'))) {
      await modeButton.click();
    }
    samples.push(await sample(page, theme, 'light'));
    await modeButton.click();
    samples.push(await sample(page, theme, 'dark'));
  }

  await select.selectOption('araihu');
  if (await page.locator('html').evaluate((root) => root.classList.contains('dark'))) {
    await modeButton.click();
  }
  await closeAppearance(page);

  expect(samples).toHaveLength(themes.length * 2);
  for (const result of samples) {
    expect(result.rootTheme, `${result.theme}/${result.mode} root theme`).toBe(result.theme);
    expect(result.rootMode, `${result.theme}/${result.mode} root mode`).toBe(result.mode === 'dark');
    for (const [name, value] of Object.entries(result.variables)) {
      expect(value, `${result.theme}/${result.mode} ${name}`).not.toBe('');
    }
    for (const [area, styles] of Object.entries({ body: result.body, panel: result.panel, control: result.control })) {
      for (const [property, value] of Object.entries(styles)) {
        expect(value, `${result.theme}/${result.mode} ${area}.${property}`).not.toBe('');
        if (property === 'background') {
          expect(value, `${result.theme}/${result.mode} ${area}.${property}`).not.toBe('rgba(0, 0, 0, 0)');
        }
      }
    }
  }
}
