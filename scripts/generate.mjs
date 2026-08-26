import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const cache = join(root, '.cache', 'sources');
const destination = join(root, 'web');
const expectedTemplates = [
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
];
const assetCopies = new Map([
  ['brand/araihu/logo/adaptive-transparent-optical.svg', 'araihu-logo.svg'],
  ['platform/web/araihu/favicon.svg', 'favicon.svg'],
  ['platform/web/araihu/favicon-32.png', 'favicon-32.png'],
]);
const fontCopies = new Map([
  ['node_modules/@fontsource/lato/files/lato-latin-400-normal.woff2', 'araihu-lato-latin-400.woff2'],
  ['node_modules/@fontsource/lato/files/lato-latin-700-normal.woff2', 'araihu-lato-latin-700.woff2'],
]);
const iconIDs = ['hi-24-outline-moon', 'hi-24-outline-sun'];
const beginOptions = '<!-- BEGIN GENERATED THEME OPTIONS -->';
const endOptions = '<!-- END GENERATED THEME OPTIONS -->';
const themeDefaultKeysMarker = '__ARAIHU_DEX_THEME_KEYS__';

function normalize(text) {
  return `${text.replaceAll('\r\n', '\n').replace(/\n*$/, '')}\n`;
}

function html(text) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

async function readCatalog() {
  const catalog = normalize(await readFile(join(cache, 'goshtoso', 'theme-catalog.txt'), 'utf8'));
  const entries = catalog.trimEnd().split('\n').map((line) => line.split('\t'));
  assert.equal(entries.length, 16, 'theme catalog must contain exactly 16 entries');
  const keys = new Set();
  for (const fields of entries) {
    assert.equal(fields.length, 2, 'theme catalog lines must be key<TAB>label');
    const [key, label] = fields;
    assert.match(key, /^[a-z0-9]+(?:-[a-z0-9]+)*$/, `invalid theme key: ${key}`);
    assert.ok(label && !/[\r\n\t]/.test(label), `invalid theme label: ${label}`);
    assert.ok(!keys.has(key), `duplicate theme key: ${key}`);
    keys.add(key);
  }
  return { catalog, entries };
}

function renderHeader(source, entries) {
  assert.equal(source.indexOf(beginOptions), source.lastIndexOf(beginOptions), 'theme option begin marker must be unique');
  assert.equal(source.indexOf(endOptions), source.lastIndexOf(endOptions), 'theme option end marker must be unique');
  const begin = source.indexOf(beginOptions);
  const end = source.indexOf(endOptions);
  assert.ok(begin >= 0 && end > begin, 'theme option markers must be ordered');
  const options = entries
    .map(([key, label]) => `          <option value="${html(key)}">${html(label)}</option>`)
    .join('\n');
  return normalize(
    `${source.slice(0, begin + beginOptions.length)}\n${options}\n          ${source.slice(end)}`,
  );
}

function renderIcons(source) {
  const symbols = iconIDs.map((id) => {
    const marker = `<symbol id="${id}"`;
    const start = source.indexOf(marker);
    assert.ok(start >= 0, `released icon missing: ${id}`);
    assert.equal(source.indexOf(marker, start + marker.length), -1, `released icon duplicated: ${id}`);
    const end = source.indexOf('</symbol>', start);
    assert.ok(end >= 0, `released icon is incomplete: ${id}`);
    return source.slice(start, end + '</symbol>'.length);
  });
  return `<svg xmlns="http://www.w3.org/2000/svg">${symbols.join('')}</svg>\n`;
}

async function manifestFiles(directory) {
  const files = [];
  async function walk(current) {
    const entries = await readdir(current, { withFileTypes: true });
    for (const entry of entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) await walk(path);
      else {
        assert.ok(entry.isFile(), `generated path must be a regular file: ${path}`);
        files.push(relative(directory, path));
      }
    }
  }
  await walk(directory);
  return files.sort();
}

async function replaceDirectory(stage) {
  const backup = `${destination}.previous-${process.pid}`;
  await rm(backup, { recursive: true, force: true });
  let hadDestination = true;
  try {
    await rename(destination, backup);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    hadDestination = false;
  }
  try {
    await rename(stage, destination);
  } catch (error) {
    if (hadDestination) await rename(backup, destination);
    throw error;
  }
  if (hadDestination) await rm(backup, { recursive: true });
}

async function main() {
  const dexTemplates = await readdir(join(cache, 'dex', 'web', 'templates'));
  assert.deepEqual(dexTemplates.sort(), expectedTemplates, 'cached Dex template inventory changed');

  const { catalog, entries } = await readCatalog();
  const themeSource = await readFile(join(cache, 'goshtoso', 'goshtoso-theme.css'), 'utf8');
  for (const [key] of entries) {
    assert.ok(themeSource.includes(`[data-theme=${key}]`), `Goshtoso theme missing: ${key}`);
  }

  const stage = await mkdtemp(join(root, '.web-stage-'));
  try {
    const templates = join(stage, 'templates');
    const staticDirectory = join(stage, 'static');
    await mkdir(templates);
    await mkdir(staticDirectory);

    const header = await readFile(join(root, 'src', 'header.html'), 'utf8');
    const footer = normalize(await readFile(join(root, 'src', 'footer.html'), 'utf8'));
    await writeFile(join(templates, 'header.html'), renderHeader(header, entries));
    await writeFile(join(templates, 'footer.html'), footer);
    await writeFile(join(staticDirectory, 'theme-allowlist.txt'), catalog);
    await writeFile(
      join(staticDirectory, 'appearance.js'),
      normalize(await readFile(join(root, 'src', 'appearance.js'), 'utf8')),
    );
    await writeFile(
      join(staticDirectory, 'theme-default.js'),
      normalize((await readFile(join(root, 'src', 'theme-default.js'), 'utf8'))
        .replace(themeDefaultKeysMarker, JSON.stringify(entries.map(([key]) => key)))),
    );

    for (const [source, output] of assetCopies) {
      await copyFile(join(cache, 'assets', source), join(staticDirectory, output));
    }
    for (const [source, output] of fontCopies) {
      await copyFile(join(root, source), join(staticDirectory, output));
    }
    await writeFile(
      join(staticDirectory, 'icons.svg'),
      renderIcons(await readFile(join(cache, 'assets', 'icons', 'ui', 'sprite.svg'), 'utf8')),
    );

    const invalid90sSelector = '[data-theme=90s]';
    assert.equal(themeSource.split(invalid90sSelector).length - 1, 1, 'expected one Goshtoso 90s selector');
    const compileTheme = join(stage, '.goshtoso-theme.css');
    const compileAdapter = join(stage, '.dex-adapter.css');
    const compileInput = join(stage, '.input.css');
    await writeFile(compileTheme, themeSource.replace(invalid90sSelector, '[data-theme="90s"]'));
    await copyFile(join(root, 'src', 'dex-adapter.css'), compileAdapter);
    const sourceDirectory = join(root, 'src');
    const input = await readFile(join(sourceDirectory, 'input.css'), 'utf8');
    await writeFile(
      compileInput,
      input
        .replace('../.cache/sources/goshtoso/goshtoso-theme.css', './.goshtoso-theme.css')
        .replace('./dex-adapter.css', './.dex-adapter.css')
        .replaceAll('../.cache/', `${root}/.cache/`)
        .replaceAll('@source "./', `@source "${sourceDirectory}/`),
    );

    execFileSync(join(root, 'node_modules', '.bin', 'tailwindcss'), [
      '-i',
      compileInput,
      '-o',
      join(staticDirectory, 'araihu-styles.css'),
      '--minify',
    ], { cwd: root, stdio: 'inherit' });
    const cssPath = join(staticDirectory, 'araihu-styles.css');
    await writeFile(cssPath, normalize(await readFile(cssPath, 'utf8')));

    await rm(compileTheme);
    await rm(compileAdapter);
    await rm(compileInput);

    assert.deepEqual((await readdir(templates)).sort(), ['footer.html', 'header.html']);
    const files = await manifestFiles(stage);
    assert.equal(files.some((path) => path.startsWith('templates/') && !/templates\/(?:header|footer)\.html$/.test(path)), false);
    const checksums = [];
    for (const path of files) {
      const digest = createHash('sha256').update(await readFile(join(stage, path))).digest('hex');
      checksums.push(`${digest}  ${path}`);
    }
    await writeFile(join(stage, 'manifest.sha256'), `${checksums.join('\n')}\n`);
    await replaceDirectory(stage);
  } catch (error) {
    await rm(stage, { recursive: true, force: true });
    throw error;
  }
}

await main();
