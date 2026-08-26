# AraiHu Dex Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan.

> **Post-implementation adjustment (2026-08-25):** Dex's native `logo` value
> and `theme/favicon.png` remain the default branding contract. Packaged AraiHu
> assets are optional overrides through normal Dex configuration or mounted
> theme paths. Goshtoso tokens, theme selection, storage consent, and all
> authentication-flow boundaries remain unchanged.

**Goal:** Build and verify a thin, AraiHu-branded overlay image at `ghcr.io/araihu/dex` while preserving the official Dex `master` authentication frontend and logic.

**Architecture:** Generate deterministic CSS/asset bytes from pinned Goshtoso and AraiHu Assets releases, copy only shared header/footer and branded static files over a digest-pinned official Dex image, then validate `ARAIHU_DEX_THEME` in a minimal shell entrypoint before delegating to Dex's original entrypoint. The implementation never vendors or overrides flow templates. Platform image manifests/configuration are reproducible; BuildKit attestation envelopes are verified by subject digest and may vary per invocation.

**Tech Stack:** Docker BuildKit/buildx, POSIX `sh`, Node.js built-ins, Tailwind CSS 4.3.3, Playwright, Axe, Cosign, Syft/BuildKit SBOM and GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-25-araihu-dex-container-design.md`

## Global Constraints

- Work only in `/Users/guilhermecastro/repos/araihu/dex` after this plan is approved.
- Initialize branch `main`; the locked upstream Dex branch remains `master`.
- Use Git identity `Guilherme de Castro <guilherme.castro@totvs.com.br>` and verify it before the first commit.
- Do not create `github.com/araihu/dex` until the user chooses repository visibility.
- Do not push, tag, release, publish an image, or edit `/Users/guilhermecastro/repos/home-lab` without a separate explicit approval.
- Keep the final image free of Node, Go, Tailwind, test tools, package-manager caches, and downloaded source archives.
- Override only `web/templates/header.html`, `web/templates/footer.html`, overlay-owned files below `web/static/`, and the AraiHu logo/favicon files. Never copy a flow template into the final image.
- Treat these baseline values as immutable until an explicit update task changes the lock:

```text
DEX_COMMIT=ab64ed778070e983cbb10cfc07ea4bb397d14312
DEX_IMAGE=ghcr.io/dexidp/dex:v2.46.0-20260806171424-ab64ed77@sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b
GOSHTOSO_VERSION=v0.2.7
ARAIHU_ASSETS_VERSION=v0.2.3
TAILWIND_VERSION=4.3.3
NODE_VERSION=26.5.0
NPM_VERSION=11.17.0
PLAYWRIGHT_VERSION=1.62.1
AXE_PLAYWRIGHT_VERSION=4.13.0
ACTIONLINT_VERSION=v1.7.7
```

- Run all generation and tests with `GOWORK=off` whenever Go is invoked for the released Goshtoso CLI.
- Every non-trivial branch needs one focused executable test; avoid helper frameworks when Node built-ins or shell assertions suffice.

---

## Task 1: Initialize the local repository and carry approved documents

**Files:**

- Create: `/Users/guilhermecastro/repos/araihu/dex/.gitignore`
- Create: `/Users/guilhermecastro/repos/araihu/dex/LICENSE`
- Create: `/Users/guilhermecastro/repos/araihu/dex/NOTICE`
- Create: `/Users/guilhermecastro/repos/araihu/dex/README.md`
- Copy: `/Users/guilhermecastro/repos/araihu/dex/docs/superpowers/specs/2026-08-25-araihu-dex-container-design.md`
- Copy: `/Users/guilhermecastro/repos/araihu/dex/docs/superpowers/plans/2026-08-25-araihu-dex-container-implementation.md`

- [ ] Verify the target is still absent; stop rather than adopting an unexpected directory.

```sh
test ! -e /Users/guilhermecastro/repos/araihu/dex
```

Expected: exit 0 with no output.

- [ ] Create the directory, initialize `main`, and set the established identity.

```sh
mkdir /Users/guilhermecastro/repos/araihu/dex
git -C /Users/guilhermecastro/repos/araihu/dex init -b main
git -C /Users/guilhermecastro/repos/araihu/dex config user.name 'Guilherme de Castro'
git -C /Users/guilhermecastro/repos/araihu/dex config user.email 'guilherme.castro@totvs.com.br'
```

- [ ] Add Apache-2.0 licensing, a NOTICE that distinguishes Dex, Goshtoso, AraiHu Assets, brand terms, and Heroicons, plus a README that repeats every lifecycle gate.
- [ ] Add `.gitignore` entries only for `.cache/`, `node_modules/`, `test-results/`, `playwright-report/`, and local image archives.
- [ ] Copy the approved spec and plan verbatim into the repository.
- [ ] Verify identity, branch, no remote, and document equality.

```sh
test "$(git config user.name)" = 'Guilherme de Castro'
test "$(git config user.email)" = 'guilherme.castro@totvs.com.br'
test "$(git branch --show-current)" = main
test -z "$(git remote)"
cmp docs/superpowers/specs/2026-08-25-araihu-dex-container-design.md \
  /Users/guilhermecastro/.codex/visualizations/2026/08/25/01a036df-338a-7662-a2c1-d3dd3fb3ac64/docs/superpowers/specs/2026-08-25-araihu-dex-container-design.md
```

- [ ] Commit only the repository foundation.

```sh
git add .gitignore LICENSE NOTICE README.md docs
git commit -m 'docs: establish AraiHu Dex overlay contract'
```

## Task 2: Add one machine-readable lock and source verification

**Files:**

- Create: `versions.env`
- Create: `scripts/fetch-sources.sh`
- Create: `test/fetch-sources_test.sh`
- Modify: `README.md`

- [ ] Write the failing shell test first. It must cover a valid cache, a bad Dex archive checksum, a bad Assets release checksum, and an extracted-member checksum mismatch.

```sh
#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

FETCH_CACHE="$tmp/cache" "$repo/scripts/fetch-sources.sh"
test -f "$tmp/cache/dex/web/templates/webauthn_verify.html"
test -f "$tmp/cache/goshtoso/goshtoso-theme.css"
test -f "$tmp/cache/assets/platform/web/araihu/favicon.svg"

printf 'corrupt\n' >>"$tmp/cache/downloads/dex.tar.gz"
if FETCH_CACHE="$tmp/cache" "$repo/scripts/fetch-sources.sh" 2>"$tmp/error"; then
  echo 'expected checksum failure' >&2
  exit 1
fi
grep -F 'Dex source checksum mismatch' "$tmp/error"
```

- [ ] Run it and confirm the missing implementation fails.

```sh
sh test/fetch-sources_test.sh
```

Expected: nonzero, `scripts/fetch-sources.sh: not found`.

- [ ] Create `versions.env` using plain `KEY=value` lines. Record the approved runtime/tool baselines plus Dex source-archive SHA-256, Assets `SHA256SUMS` identity, member-manifest SHA-256, Goshtoso module sum, Tailwind package integrity, and generated theme-catalog SHA-256. Values discovered from public releases must be concrete; no `latest`, mutable URL, empty value, or placeholder is permitted.
- [ ] Implement `fetch-sources.sh` in POSIX `sh`. It loads only allowlisted keys from `versions.env`, downloads immutable sources to `.cache/downloads`, verifies before extraction, invokes the supported command below, and writes through temporary paths followed by atomic rename.

```sh
GOWORK=off go run "github.com/araihu/goshtoso/cmd/goshtoso@${GOSHTOSO_VERSION}" \
  -theme -out="$FETCH_CACHE/goshtoso/goshtoso-theme.css"
```

- [ ] Extract the public Goshtoso catalog from its pinned module source, not from demo/internal files. Generate canonical `key<TAB>label` lines from `themes.BuiltIn()` through a tiny temporary Go program created inside `.cache/`; do not add an application Go module.
- [ ] Acquire Assets only from the tagged release. Verify release `SHA256SUMS`, then the archive's `checksums.txt`, before copying catalog-addressed members.
- [ ] Reject symlinks, absolute paths, `..` members, duplicate destinations, and files not named in the extraction allowlist.
- [ ] Finish the focused test with fixture HTTP/file URLs so failure cases do not depend on mutating the public cache. Add the unset-lock and unknown-key cases.
- [ ] Run tests and a live fetch.

```sh
sh test/fetch-sources_test.sh
rm -rf .cache/sources
scripts/fetch-sources.sh
```

Expected: both commands exit 0; the cache contains exact Dex templates, Goshtoso theme source/catalog, approved brand assets, and notices.

- [ ] Commit lock and acquisition boundary.

```sh
git add versions.env scripts/fetch-sources.sh test/fetch-sources_test.sh README.md
git commit -m 'build: pin and verify frontend sources'
```

## Task 3: Generate the minimal overlay deterministically

**Files:**

- Create: `package.json`
- Create: `package-lock.json`
- Create: `.node-version`
- Create: `src/input.css`
- Create: `src/dex-adapter.css`
- Create: `src/header.html`
- Create: `src/footer.html`
- Create: `src/appearance.js`
- Create: `scripts/generate.mjs`
- Create: `test/generate.test.mjs`
- Create/generated: `web/templates/header.html`
- Create/generated: `web/templates/footer.html`
- Create/generated: `web/static/araihu-styles.css`
- Create/generated: `web/static/appearance.js`
- Create/generated: `web/static/theme-allowlist.txt`
- Create/generated: `web/static/araihu-logo.svg`
- Create/generated: `web/static/favicon.svg`
- Create/generated: `web/static/favicon-32.png`
- Create/generated: `web/static/icons.svg`
- Create/generated: `web/manifest.sha256`

- [ ] Set `.node-version` to `26.5.0` and `packageManager` to `npm@11.17.0`. Initialize the package lock with exactly Tailwind CLI 4.3.3, Tailwind 4.3.3, Playwright 1.62.1, and Axe Playwright 4.13.0 as development dependencies. Do not add a browser framework, DOM emulator, bundler, formatter, or runtime package.
- [ ] Write a failing Node built-in test that asserts deterministic bytes, the 16 public theme keys and labels, no flow template output, correct asset provenance, and a complete manifest.

```js
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import test from 'node:test';

test('generation emits only the approved overlay', async () => {
  const templates = await readdir(new URL('../web/templates/', import.meta.url));
  assert.deepEqual(templates.sort(), ['footer.html', 'header.html']);

  const allowlist = await readFile(
    new URL('../web/static/theme-allowlist.txt', import.meta.url),
    'utf8',
  );
  assert.match(allowlist, /^90s\t90s$/m);
  assert.match(allowlist, /^araihu\tArai Hû$/m);
  assert.equal(allowlist.trim().split('\n').length, 16);
});
```

- [ ] Run it before creating the generator.

```sh
node --test test/generate.test.mjs
```

Expected: nonzero because generated files do not exist.

- [ ] Base `src/header.html` and `src/footer.html` on the exact locked upstream files. Preserve the upstream issuer, URL helper, request-path expressions, and wrappers. Replace only the logo `src` and favicon links with fixed same-origin AraiHu files, then add the native selector and light/dark button. Use `aria-label`, `aria-pressed`, a real `<label>`, and `<button type="button">`.
- [ ] Link `static/araihu-styles.css` after upstream `theme/styles.css`. This keeps the client theme catalog independent of Dex's server-selected `frontend.theme` while allowing the adapter to override visual tokens last.
- [ ] Put all 16 theme options between one generated marker pair in `src/header.html`; `generate.mjs` replaces only that pair from the catalog.
- [ ] Make `src/footer.html` retain upstream closing tags and add the non-modal `gt_storage` notice immediately before `</body>`.
- [ ] Make `src/input.css` include the released Goshtoso theme source, the Dex adapter, and exact `@source` paths for all eleven cached upstream templates plus the two shared sources. Safelist only state selectors constructed by JavaScript (`dark`, the cookie notice hidden state); do not safelist broad class families.
- [ ] Map existing Dex classes in `dex-adapter.css` to Goshtoso semantic variables. Do not add selectors coupled to a specific flow, submit forms from CSS/JS, hide errors, or reorder fields.
- [ ] Implement `generate.mjs` with Node built-ins: validate the catalog, render header options, copy allowlisted assets, invoke the local Tailwind binary, normalize file order/newlines, and emit sorted SHA-256 lines. Generate into a temporary directory and replace `web/` only after every check passes.
- [ ] Have the generator assert that the cached Dex inventory is exactly the eleven locked templates and that only header/footer differ in the final overlay.
- [ ] Run generation twice and prove byte identity.

```sh
npm ci
scripts/fetch-sources.sh
npm run generate
cp web/manifest.sha256 /tmp/araihu-dex-manifest.sha256
npm run generate
cmp web/manifest.sha256 /tmp/araihu-dex-manifest.sha256
node --test test/generate.test.mjs
```

Expected: all exit 0 and `git diff -- web` is stable after the second run.

- [ ] Commit sources and generated overlay together.

```sh
git add .node-version package.json package-lock.json src scripts/generate.mjs \
  test/generate.test.mjs web
git commit -m 'feat: generate AraiHu Dex frontend overlay'
```

## Task 4: Implement client appearance and storage without auth coupling

**Files:**

- Modify: `src/appearance.js`
- Modify: `test/generate.test.mjs`
- Create: `test/appearance.spec.ts`
- Modify/generated: `web/static/appearance.js`
- Modify/generated: `web/manifest.sha256`

- [ ] Write browser tests first for precedence and failure behavior:

```ts
test('denied storage changes only the current page', async ({ page, baseURL }) => {
  await page.context().addCookies([{
    name: 'gt_storage', value: 'denied', url: baseURL!,
  }]);
  await page.goto('/auth/local');
  await page.getByLabel('Tema').selectOption('dracula');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dracula');
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'araihu');
});

test('storage exceptions do not break login', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, 'localStorage', {
      get() { throw new DOMException('blocked', 'SecurityError'); },
    });
  });
  await page.goto('/auth/local');
  await expect(page.locator('form')).toBeVisible();
  await expect(page).toHaveURL(/\/auth\/local/);
});
```

- [ ] Run the focused suite and confirm failure before behavior is implemented.

```sh
npx playwright test test/appearance.spec.ts
```

Expected: nonzero with missing control/behavior assertions.

- [ ] Implement one closure in `appearance.js`, no exported library API. Validate every theme read from runtime or storage against the generated `<select>` options.
- [ ] Apply startup precedence exactly: validated persisted preference when `gt_storage=allowed`; otherwise runtime default; then `prefers-color-scheme` only for dark mode when no allowed preference exists.
- [ ] Write `gt_storage=allowed|denied; Path=/; Max-Age=15552000; SameSite=Lax`. Never add `Domain`, `Secure` conditionals, analytics IDs, or reads of Dex cookies.
- [ ] On deny, remove only `theme` and `darkMode`, matching the approved AraiHu host-local contract. On exceptions, keep in-memory behavior and suppress only expected storage-access errors.
- [ ] Theme/light controls must update `data-theme`, `.dark`, `aria-pressed`, and the button's accessible label without touching forms or auth events.
- [ ] Regenerate and run focused tests.

```sh
npm run generate
node --test test/generate.test.mjs
npx playwright test test/appearance.spec.ts
```

Expected: all pass; browser console contains no uncaught overlay errors.

- [ ] Commit the appearance boundary.

```sh
git add src/appearance.js test/appearance.spec.ts web
git commit -m 'feat: add consent-aware theme switching'
```

## Task 5: Add the runtime wrapper and thin image

**Files:**

- Create: `entrypoint.sh`
- Create: `Dockerfile`
- Create: `.dockerignore`
- Create: `src/theme-default.js`
- Modify: `scripts/generate.mjs`
- Create/generated: `web/static/theme-default.js`
- Modify/generated: `web/manifest.sha256`
- Create: `test/entrypoint_test.sh`
- Create: `test/image-overlay_test.sh`

- [ ] Write entrypoint tests first using a temporary fake upstream entrypoint. Cover: `DEX_FRONTEND_DIR=` bypasses all validation; theme unset; theme empty; `araihu`; every allowlisted key; unknown; padded; case-modified; and failed output write.

```sh
DEX_FRONTEND_DIR='' ARAIHU_DEX_THEME=' invalid ' \
  THEME_DEFAULT_FILE="$tmp/theme-default.js" \
  UPSTREAM_ENTRYPOINT="$tmp/upstream" ./entrypoint.sh serve
test "$(cat "$tmp/argv")" = 'serve'

if ARAIHU_DEX_THEME=' araihu ' THEME_DEFAULT_FILE="$tmp/theme-default.js" \
  UPSTREAM_ENTRYPOINT="$tmp/upstream" \
  ./entrypoint.sh serve 2>"$tmp/error"; then
  exit 1
fi
grep -F 'invalid ARAIHU_DEX_THEME' "$tmp/error"
```

- [ ] Run it and confirm the missing wrapper fails.

```sh
sh test/entrypoint_test.sh
```

Expected: nonzero, `./entrypoint.sh: not found`.

- [ ] Implement a POSIX shell wrapper with only three branches: explicit empty frontend rollback, exact theme allowlist validation, and rendering of writable `theme-default.js` from the root-owned immutable template before `exec` of `${UPSTREAM_ENTRYPOINT:-/usr/local/bin/docker-entrypoint}`. Repeated starts always regenerate from that template, so a partial served file is never executed. Do not use `eval`, `envsubst`, JSON tools, or log environment values.
- [ ] Add a generated parser-blocking `theme-default.js` bootstrap with the released theme-key allowlist, synchronous cookie/localStorage fallback, and a validated default-theme marker; include it in the manifest. The image copies the rendered output as `1001:1001` and the same generated marker source as root-owned `theme-default.template.js`.
- [ ] Write a single-stage final Dockerfile `FROM ghcr.io/dexidp/dex:<approved-prerelease>@sha256:...`. Copy only the two shared templates, the immutable theme bootstrap source, `web/static/araihu-*`, appearance/default scripts, approved logo/favicon/icons, notices, and wrapper. Use `COPY --chown=1001:1001` for writable overlay files and root ownership for the immutable source; keep `USER 1001:1001`; set `DEX_FRONTEND_DIR=/srv/dex/web`; set the wrapper as `ENTRYPOINT`; preserve upstream CMD.
- [ ] Add a static allowlist assertion to `image-overlay_test.sh`: compare filesystem listings of the upstream and derived images and fail if a flow template differs or any unapproved path appears.
- [ ] Build and test the local image.

```sh
docker buildx build --load --platform linux/arm64 -t araihu-dex:test .
sh test/entrypoint_test.sh
sh test/image-overlay_test.sh araihu-dex:test
docker run --rm -e ARAIHU_DEX_THEME=unknown araihu-dex:test serve /etc/dex/config.yaml
```

Expected: the first three commands pass; the last exits nonzero before Dex and prints only the invalid-value diagnostic.

- [ ] Test embedded-frontend rollback with the same image.

```sh
docker run --rm -e DEX_FRONTEND_DIR= -e ARAIHU_DEX_THEME=unknown \
  araihu-dex:test --help
```

Expected: upstream Dex help exits 0, proving invalid overlay settings are bypassed when the frontend is disabled.

- [ ] Commit image boundary.

```sh
git add entrypoint.sh Dockerfile .dockerignore src/theme-default.js \
  scripts/generate.mjs web/static/theme-default.js web/manifest.sha256 \
  test/entrypoint_test.sh test/image-overlay_test.sh
git commit -m 'build: layer overlay on pinned Dex master image'
```

## Task 6: Exercise real Dex semantics, MFA, CSP, and screenshots

**Files:**

- Create: `test/fixtures/dex.yaml`
- Create: `test/fixtures/csp-proxy.mjs`
- Create: `test/semantic.spec.ts`
- Create: `test/visual.spec.ts`
- Create: `test/accessibility.spec.ts`
- Create: `playwright.config.ts`
- Create: `test/screenshots/araihu/` baselines
- Create: `scripts/test-image.sh`

- [ ] Create an isolated Dex config using SQLite in a temporary directory, one static password connector, a local OAuth client, sessions, TOTP, and WebAuthn. No real user, secret, network service, or homelab path may be used.
- [ ] Make `test-image.sh` start the real derived container on an ephemeral localhost port, wait on `/healthz`, run Playwright, and always stop/remove the container with a trap.
- [ ] Write semantic assertions before screenshot assertions. For every flow, compare the rendered form method/action, field names, hidden values, constraints, labels, and submit values against the locked upstream fixture.
- [ ] Cover all eleven templates through real routes/states: login, password error, approval with/without scopes, generic error, device entry/success, OOB, home, logout, TOTP enrollment/invalid/valid, and WebAuthn register/login.
- [ ] Use Playwright's virtual authenticator for WebAuthn. Assert upstream begin/finish URLs and retryable cancellation/timeout/security/server-error states; never stub or replace the template's WebAuthn JavaScript.
- [ ] Add a local CSP proxy that expresses only the allowances already needed by locked upstream Dex plus same-origin external overlay files. Assert no overlay-specific inline script requirement and retain `img-src data:` for TOTP QR.
- [ ] Add Axe checks, visible focus, names/roles/states, 390 px clipping/obstruction, and reduced-motion checks. Fail on critical violations and unexpected console/page errors.
- [ ] Capture committed AraiHu baselines for every meaningful state at 390 and 1440 pixels, light and dark. Mask only dynamic QR pixels while asserting QR presence, size, and alt text.
- [ ] Capture artifact-only login screenshots for every other allowlisted theme at both widths and modes; run computed-style smoke checks for every theme on every page.
- [ ] Run the full local acceptance suite.

```sh
scripts/test-image.sh araihu-dex:test
```

Expected: all semantic, storage, accessibility, CSP, WebAuthn, TOTP, and visual assertions pass; no unexpected console errors.

- [ ] Run the embedded-frontend rollback suite against both the derived image
  with `DEX_FRONTEND_DIR=` and the exact pinned upstream image.

```sh
DOCKER_DEFAULT_PLATFORM=linux/amd64 DEX_TEST_FRONTEND_DIR= \
  scripts/test-image.sh araihu-dex:test test/rollback.spec.ts
DOCKER_DEFAULT_PLATFORM=linux/amd64 DEX_TEST_FRONTEND_DIR= \
  scripts/test-image.sh \
  ghcr.io/dexidp/dex:v2.46.0-20260806171424-ab64ed77@sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b \
  test/rollback.spec.ts
```

Expected: login, consent, TOTP enrollment, WebAuthn registration, home, and
logout remain usable in both rollback targets.

- [ ] Commit tests and reviewed AraiHu baselines.

```sh
git add playwright.config.ts scripts/test-image.sh test
git commit -m 'test: lock Dex semantics and visual evidence'
```

## Task 7: Add CI and automated upstream update preparation

**Files:**

- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/update-upstream.yml`
- Create: `scripts/update-lock.sh`
- Create: `test/update-lock_test.sh`
- Modify: `README.md`

- [ ] Test update logic with fixtures before adding the workflow. Cover mismatched revision label/digest, changed template inventory, failed shared-template rebase, changed WebAuthn script, and a valid no-op update.
- [ ] Implement `update-lock.sh` to accept the approved prerelease as the initial lock, then resolve one Dex `master` commit and matching multi-arch digest, read the official pseudo-version label, verify `org.opencontainers.image.revision`, verify the official signature/provenance identity, update immutable values, refresh cached fixtures, regenerate, and run focused drift checks. It must not commit, push, create a PR, tag, or publish.
- [ ] Make `ci.yml` run on pull requests and `main` pushes with only `contents: read` and `packages: read`. Pin every action by full commit SHA with its release tag in a comment.
- [ ] CI order: `npm ci`; lock/source verification; generation; `git diff --exit-code`; shell tests; Node tests; build arm64 and amd64; filesystem-overlay diff; real-image acceptance; vulnerability scan; upload screenshot/report artifacts.
- [ ] Ensure PR jobs build to the local BuildKit cache only. No registry login, package write permission, image tag, attestation, or signing step exists in CI.
- [ ] Make `update-upstream.yml` weekly plus manual dispatch. Give only `contents: write` and `pull-requests: write`; use GitHub's token and `gh pr create`, not a third-party PR action.
- [ ] Fail update workflow before branch creation unless all local update checks pass. The generated PR body must state old/new commit and digest, template inventory, WebAuthn diff status, generated manifest digest, and required human screenshot review.
- [ ] Lint workflow YAML and run update tests locally.

```sh
sh test/update-lock_test.sh
GOWORK=off go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7
git diff --check
```

Expected: all exit 0.

- [ ] Commit CI/update preparation.

```sh
git add .github scripts/update-lock.sh test/update-lock_test.sh README.md
git commit -m 'ci: verify overlay and prepare upstream updates'
```

## Task 8: Prepare, but do not execute, the GHCR release workflow

**Files:**

- Create: `.github/workflows/release.yml`
- Create: `scripts/verify-release.sh`
- Create: `test/release-policy_test.sh`
- Modify: `README.md`
- Modify: `NOTICE`

- [ ] Write a policy test that parses the workflow and rejects non-`v*` triggers, mutable base images, extra platforms, broad permissions, PR publication, `master`/`edge` tags, missing SBOM/provenance, or missing keyless signature verification.
- [ ] Configure stable tags only: `vX.Y.Z`, `X.Y`, `X`, and `latest`. Reject prerelease tags until separately designed.
- [ ] Build exactly `linux/amd64,linux/arm64` to `ghcr.io/araihu/dex`. Emit OCI labels for AraiHu revision/version, upstream commit/digest, Goshtoso/Assets versions, creation time, source, and licenses.
- [ ] Verify the local OCI archive, bind its root digest to the temporary candidate reference, and promote only that verified candidate digest to stable aliases.
- [ ] Use BuildKit provenance plus SPDX JSON SBOM, GitHub artifact attestation, and Cosign keyless signing bound to the release workflow identity. Upload manifest/checksum, SBOM, scan, and screenshot evidence.
- [ ] Set workflow permissions exactly to `contents: read`, `packages: write`, `id-token: write`, and `attestations: write`. Do not add deployments, environments, secrets, or homelab credentials.
- [ ] Give `verify-release.sh` two explicit modes. `local <oci.tar>` validates index platforms, per-platform labels, identical frontend manifest bytes, and embedded SBOM/provenance. `remote <image-ref>` additionally validates the published subject, signature identity, and tag mapping.
- [ ] Document the external gates: repository creation/visibility, first push, tag authorization, and GHCR publication are separate approvals. The workflow file being present grants none of them.
- [ ] Run policy checks without logging into GHCR.

```sh
sh test/release-policy_test.sh
GOWORK=off go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7
git diff --check
```

Expected: all exit 0; no remote or registry state exists.

- [ ] Commit release preparation.

```sh
git add .github/workflows/release.yml scripts/verify-release.sh \
  test/release-policy_test.sh README.md NOTICE
git commit -m 'ci: prepare signed multi-architecture releases'
```

### Task 8 review-fix ledger

Review rejection addressed by `773ba305e790c8671080ca366070ca95a34575f4`:

- update preparation derives the official Dex pseudo-version label and writes
  an immutable version-tag-plus-digest lock;
- the release workflow binds the temporary candidate digest to the locally
  verified OCI archive before signing, attesting, remote verification, and
  stable-alias promotion;
- local attestation verification enforces in-toto type, per-platform subject
  name/digest, and non-empty SPDX/SLSA predicate bodies;
- update/release policy tests and SDD evidence pass; no publication or remote
  lifecycle action was executed.

## Task 9: Fresh verification and implementation review

**Files:**

- Review: all tracked files
- Modify only files required by findings

- [ ] Confirm the repository remains local and no prohibited target changed.

```sh
test -z "$(git remote)"
test ! -e /Users/guilhermecastro/repos/home-lab/.git/index.lock
git status --short
```

Expected: no remote, no homelab lock, clean worktree before review.

- [ ] Rebuild from a cold source cache and run every local gate.

```sh
rm -rf .cache node_modules test-results playwright-report
npm ci
scripts/fetch-sources.sh
npm run generate
git diff --exit-code
sh test/fetch-sources_test.sh
sh test/entrypoint_test.sh
sh test/image-overlay_test.sh araihu-dex:test
node --test test/generate.test.mjs
sh test/update-lock_test.sh
sh test/release-policy_test.sh
GOWORK=off go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.7
scripts/test-image.sh araihu-dex:test
git diff --check
```

Expected: all exit 0, including clean generated output.

- [ ] Build both target architectures and inspect without pushing.

```sh
docker buildx build --platform linux/amd64,linux/arm64 \
  --output type=oci,dest=/tmp/araihu-dex.oci.tar .
scripts/verify-release.sh local /tmp/araihu-dex.oci.tar
```

Expected: exactly amd64/arm64; identical overlay manifest; locked upstream revision labels.

- [ ] Perform one scoped self-review against every spec acceptance criterion. Specifically inspect auth form invariants, cookie boundaries, CSP, wrapper rollback precedence, image file diff, workflow permissions, license evidence, and absence of placeholders.
- [ ] Run the placeholder scan and inspect every hit rather than blindly replacing legitimate words.

```sh
rg -n 'TODO|FIXME|TBD|PLACEHOLDER|example\.com|latest|:master(\s|$)' \
  --glob '!docs/superpowers/**' .
```

Expected: no unresolved placeholder or mutable dependency; documented references to upstream `master` must still be digest-pinned.

- [ ] Fix findings with focused tests, rerun affected gates, then rerun the full cold verification.
- [ ] Stop with a local clean `main` and report exact commits and evidence. Do not add a remote or create GitHub/GHCR state.

## Post-implementation authorization gates

These are deliberately outside implementation and must happen in separate user-approved turns:

1. Ask whether `github.com/araihu/dex` should be public or private; only then create it.
2. Ask before adding/pushing the GitHub remote.
3. Review GitHub Actions results on the exact pushed commit.
4. Ask before creating the first `vX.Y.Z` tag or GitHub Release.
5. Ask before allowing `ghcr.io/araihu/dex` publication.
6. Defer all `/Users/guilhermecastro/repos/home-lab` image adoption and deployment to a separate authorized task.
