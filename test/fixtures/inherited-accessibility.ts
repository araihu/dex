import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import AxeBuilder from '@axe-core/playwright';
import { expect, type Page } from '@playwright/test';

const inheritedCritical = {
  device: {
    pathname: '/device',
    template: 'device.html',
    sha256: '1e8360eb5a07219a2805f0bb62f39dc8f5bc92ee17c981ecdb59e8b33049df84',
    violations: [{ rule: 'label', target: '#user_code' }],
  },
  oob: {
    pathname: '/auth',
    template: 'oob.html',
    sha256: '4c37a3db757039c90532530f4d6c73633bb604d1b292a9ac3107ac312a134f7e',
    violations: [{ rule: 'label', target: 'input' }],
  },
} as const;

export type InheritedCriticalPage = keyof typeof inheritedCritical;

async function assertLockedTemplateIdentity(key: InheritedCriticalPage) {
  const contract = inheritedCritical[key];
  const fixture = await readFile(new URL(`../../.cache/sources/dex/web/templates/${contract.template}`, import.meta.url));
  expect(createHash('sha256').update(fixture).digest('hex')).toBe(contract.sha256);

  const container = process.env.DEX_TEST_CONTAINER;
  assert.ok(container, 'DEX_TEST_CONTAINER is required; run scripts/test-image.sh');
  const live = execFileSync('docker', [
    'exec', container, 'cat', `/srv/dex/web/templates/${contract.template}`,
  ]);
  expect(live).toEqual(fixture);
  expect(createHash('sha256').update(live).digest('hex')).toBe(contract.sha256);
}

export async function assertCriticalAxe(page: Page, inherited?: InheritedCriticalPage) {
  const { violations } = await new AxeBuilder({ page }).analyze();
  const actual = violations
    .filter(({ impact }) => impact === 'critical')
    .flatMap(({ id, nodes }) => nodes.map(({ target }) => ({
      rule: id,
      target: target.join(' '),
    })));

  if (!inherited) {
    expect(actual).toEqual([]);
    return;
  }

  const contract = inheritedCritical[inherited];
  expect(new URL(page.url()).pathname).toBe(contract.pathname);
  await assertLockedTemplateIdentity(inherited);
  expect(actual).toEqual(contract.violations);
}
