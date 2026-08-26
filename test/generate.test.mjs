import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const web = new URL('web/', root);

const expectedCatalog = `90s\t90s
araihu\tArai Hû
arctic\tArctic
christmas\tChristmas
dracula\tDracula
goshtoso\tGoshtoso
halloween\tHalloween
high-contrast\tHigh Contrast
industrial\tIndustrial
minimal\tMinimal
modern\tModern
neo-brutalism\tNeo Brutalism
news\tNews
pastel\tPastel
prototype\tPrototype
zombie\tZombie
`;

const expectedFiles = [
  'static/appearance.js',
  'static/araihu-logo.svg',
  'static/araihu-styles.css',
  'static/favicon-32.png',
  'static/favicon.svg',
  'static/icons.svg',
  'static/theme-allowlist.txt',
  'static/theme-default.js',
  'templates/footer.html',
  'templates/header.html',
];

async function bytes(path) {
  return readFile(new URL(path, web));
}

async function snapshot() {
  return Promise.all([...expectedFiles, 'manifest.sha256'].map(async (path) => [path, await bytes(path)]));
}

test('generation emits only the approved deterministic overlay', async () => {
  assert.deepEqual((await readdir(new URL('templates/', web))).sort(), [
    'footer.html',
    'header.html',
  ]);
  assert.deepEqual((await readdir(new URL('static/', web))).sort(), [
    'appearance.js',
    'araihu-logo.svg',
    'araihu-styles.css',
    'favicon-32.png',
    'favicon.svg',
    'icons.svg',
    'theme-allowlist.txt',
    'theme-default.js',
  ]);

  assert.equal(await bytes('static/theme-allowlist.txt').then(String), expectedCatalog);

  const header = await bytes('templates/header.html').then(String);
  assert.match(header, /<html lang="en">/);
  assert.match(header, /<title>{{ issuer }}<\/title>/);
  assert.match(header, /{{ url \.ReqPath "theme\/styles\.css" }}/);
  assert.match(header, /{{ url \.ReqPath "static\/araihu-styles\.css" }}/);
  assert.ok(
    header.indexOf('theme/styles.css') < header.indexOf('static/araihu-styles.css'),
    'overlay stylesheet must load after upstream theme stylesheet',
  );
  assert.match(header, /<details class="araihu-appearance">/);
  assert.match(header, /<summary class="araihu-appearance-trigger">Appearance<\/summary>/);
  assert.match(header, /<label[^>]+for="araihu-theme">Theme<\/label>/);
  assert.match(header, /<span class="araihu-theme-select">\s*<select[^>]+id="araihu-theme"[^>]+aria-label="Theme"/);
  assert.match(header, /<button[^>]+type="button"[^>]+aria-label="Switch to dark mode"[^>]+aria-pressed="false"/);
  assert.match(header, /<main class="dex-container">/);
  const scripts = [...header.matchAll(/<script\b[^>]*>/g)].map((match) => match[0]);
  assert.deepEqual(scripts, [
    '<script src="{{ url .ReqPath "static/theme-default.js" }}">',
    '<script defer src="{{ url .ReqPath "static/appearance.js" }}">',
  ]);
  assert.ok(
    header.indexOf('static/theme-default.js') < header.indexOf('static/appearance.js'),
    'runtime default must load before the appearance controller',
  );
  assert.equal((header.match(/<option value=/g) ?? []).length, 16);
  assert.match(header, /<img class="theme-navbar__logo" src="{{ url \.ReqPath logo }}" alt="{{ issuer }}">/);
  assert.match(header, /{{ url \.ReqPath "theme\/favicon\.png" }}/);

  const footer = await bytes('templates/footer.html').then(String);
  assert.match(footer, /id="araihu-storage-notice"/);
  assert.match(footer, /Save appearance preferences in this browser\?/);
  assert.match(footer, />Save<\/button>/);
  assert.match(footer, />Not now<\/button>/);
  assert.match(footer, /data-storage-choice="allowed"/);
  assert.match(footer, /data-storage-choice="denied"/);
  assert.match(footer, /<\/body>\n<\/html>\n$/);

  const provenance = new Map([
    ['static/appearance.js', 'src/appearance.js'],
    ['static/araihu-logo.svg', '.cache/sources/assets/brand/araihu/logo/adaptive-transparent-optical.svg'],
    ['static/favicon.svg', '.cache/sources/assets/platform/web/araihu/favicon.svg'],
    ['static/favicon-32.png', '.cache/sources/assets/platform/web/araihu/favicon-32.png'],
  ]);
  for (const [output, source] of provenance) {
    assert.deepEqual(await bytes(output), await readFile(new URL(source, root)), output);
  }

  const themeDefault = await bytes('static/theme-default.js').then(String);
  assert.match(themeDefault, /^window\.__araihuDexDefaultTheme = "__ARAIHU_DEX_DEFAULT_THEME__";/m);
  assert.match(themeDefault, /window\.__araihuDexThemeKeys = \["90s","araihu","arctic"/);
  assert.match(themeDefault, /root\.dataset\.theme = theme;/);

  const iconSource = await readFile(new URL('.cache/sources/assets/icons/ui/sprite.svg', root), 'utf8');
  const icons = await bytes('static/icons.svg').then(String);
  const iconIDs = [...icons.matchAll(/<symbol id="([^"]+)"/g)].map((match) => match[1]);
  assert.deepEqual(iconIDs, ['hi-24-outline-moon', 'hi-24-outline-sun']);
  for (const id of iconIDs) {
    const symbol = icons.match(new RegExp(`<symbol id="${id}"[\\s\\S]*?</symbol>`));
    assert.ok(symbol && iconSource.includes(symbol[0]), `${id} must come unchanged from released sprite`);
  }

  const css = await bytes('static/araihu-styles.css').then(String);
  for (const line of expectedCatalog.trim().split('\n')) {
    const key = line.slice(0, line.indexOf('\t'));
    const selector = key === '90s' ? '[data-theme="90s"]' : `[data-theme=${key}]`;
    assert.ok(css.includes(selector), `compiled CSS must contain ${selector}`);
  }

  const manifest = await bytes('manifest.sha256').then(String);
  const lines = manifest.trim().split('\n');
  assert.deepEqual(lines.map((line) => line.slice(66)), expectedFiles);
  for (const line of lines) {
    const [expected, path] = line.split('  ');
    assert.equal(createHash('sha256').update(await bytes(path)).digest('hex'), expected, path);
  }

  const before = await snapshot();
  const generated = spawnSync(process.execPath, ['scripts/generate.mjs'], {
    cwd: root,
    encoding: 'utf8',
  });
  assert.equal(generated.status, 0, generated.stderr);
  assert.deepEqual(await snapshot(), before);
});
