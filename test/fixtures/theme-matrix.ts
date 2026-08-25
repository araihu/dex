import { readFile } from 'node:fs/promises';
import { expect, type Page } from '@playwright/test';

export const themes = (await readFile(
  new URL('../../web/static/theme-allowlist.txt', import.meta.url),
  'utf8',
)).trim().split('\n').map((line) => line.split('\t')[0]);

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
  const select = page.getByLabel('Tema');
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
