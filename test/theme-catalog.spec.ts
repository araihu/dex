import { expect, test } from '@playwright/test';
import * as themeMatrix from './fixtures/theme-matrix';

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

test('theme matrix is guarded by an independent exact ordered catalog', () => {
  expect(themeMatrix.assertExactThemeCatalog).toBeDefined();
  const assertExactThemeCatalog = themeMatrix.assertExactThemeCatalog!;

  expect(() => assertExactThemeCatalog([...exactThemeKeys])).not.toThrow();
  expect(themeMatrix.themes).toEqual(exactThemeKeys);
});

test('theme catalog rejects drop, duplicate, reorder, and extra mutations', () => {
  expect(themeMatrix.assertExactThemeCatalog).toBeDefined();
  const assertExactThemeCatalog = themeMatrix.assertExactThemeCatalog!;
  const mutations = {
    dropped: exactThemeKeys.slice(0, -1),
    duplicated: [...exactThemeKeys.slice(0, -1), 'prototype'],
    reordered: [exactThemeKeys[1], exactThemeKeys[0], ...exactThemeKeys.slice(2)],
    extra: [...exactThemeKeys, 'unexpected'],
  };

  for (const [name, mutation] of Object.entries(mutations)) {
    expect(() => assertExactThemeCatalog(mutation), name).toThrow('theme catalog must match the exact 16-key order');
  }
});
