# AraiHu Dex Container Design

**Date:** 2026-08-25  
**Status:** Approved; security-build amendment approved 2026-08-26
**Target repository:** `/Users/guilhermecastro/repos/araihu/dex`  
**Target image:** `ghcr.io/araihu/dex`

> **Password-profile amendment (2026-08-27):** The API/source non-goals below
> are superseded only for the additive, wire-compatible local-password fields
> documented in the repository README. The overlay remains pinned, verifies
> source preimages before patching, and does not change authentication logic.

## Summary

Create an AraiHu-maintained frontend overlay on the official Dex prerelease container for
commit `ab64ed778070e983cbb10cfc07ea4bb397d14312`. The image preserves Dex
authentication behavior, templates, form semantics, TOTP flow, and WebAuthn
JavaScript. It keeps Dex's native logo and favicon hooks by default, adds the
released Goshtoso theme catalog and optional AraiHu brand assets, a small
accessible client-side theme control, the established AraiHu browser-storage
consent contract, deterministic frontend assets, and verifiable supply-chain
evidence. The final
stage remains based on the official image, while Dex, its entrypoint, and
gomplate are rebuilt from their exact upstream sources with Go 1.27.0 and the
minimum patched dependencies needed by the fail-closed vulnerability gate.

The implementation is not a Dex source fork. It derives from an upstream image
pinned by multi-architecture digest, rebuilds the same Dex commit without
authentication-source patches, sets `DEX_FRONTEND_DIR=/srv/dex/web`, and
overwrites shared frontend files and branded assets already present in that
filesystem tree. Disabling `DEX_FRONTEND_DIR` restores the embedded upstream
frontend without changing stored identity data; running the pinned official
image restores the original upstream binaries.

## Goals

1. Publish an AraiHu-maintained, Goshtoso-themed Dex image at `ghcr.io/araihu/dex` after an explicit publication gate.
2. Apply any released Goshtoso theme to every Dex page, with AraiHu as the runtime default.
3. Preserve all Dex authentication logic and flow-specific frontend semantics.
4. Preserve current Dex `master` TOTP enrollment/verification and WebAuthn registration/login behavior.
5. Use released, verified material from `github.com/araihu/goshtoso` and `github.com/araihu/assets`.
6. Build source-pinned `linux/amd64` and `linux/arm64` platform images and deterministic frontend assets, with SBOM, provenance, and keyless signing.
7. Detect upstream frontend drift before it reaches a release.
8. Keep rollback to the upstream frontend or upstream image immediate and data-neutral.

## Non-goals

- No Dex authentication, storage, connector, session, MFA, API, or protocol changes.
- No Dex source fork.
- No Go/templ component imports. Dex uses Go `html/template`, not templ.
- No copying of Goshtoso demo-site or `internal/` markup or JavaScript.
- No Alpine.js, HTMX, runtime CDN, analytics, tracking, or remote fonts.
- No homelab edits or deployment.
- No GitHub repository creation until visibility is explicitly chosen.
- No push, image publication, tag, release, or deployment without explicit authorization.

## Verified public baseline

### Dex

The design baseline is official Dex commit
`ab64ed778070e983cbb10cfc07ea4bb397d14312`, published as
`ghcr.io/dexidp/dex:v2.46.0-20260806171424-ab64ed77@sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b`.
The generic `:master` tag is a discovery lane, not an accepted build contract.

That commit requires these eleven templates:

- `approval.html`
- `device.html`
- `device_success.html`
- `error.html`
- `home.html`
- `login.html`
- `logout.html`
- `oob.html`
- `password.html`
- `totp_verify.html`
- `webauthn_verify.html`

Dex loads embedded web assets unless `frontend.dir` or `DEX_FRONTEND_DIR` names a filesystem directory. Its official image already contains the matching `web` tree at `/srv/dex/web`. The locked prerelease image is Alpine-based, runs as `dex:dex` (`1001:1001`), and includes the upstream `docker-entrypoint` and `gomplate` binaries.

Dex `master` renders TOTP enrollment and verification through `totp_verify.html`. It renders WebAuthn registration and login through `webauthn_verify.html`; that template contains upstream inline WebAuthn JavaScript and an inline event handler. The overlay must not rewrite this code.

Dex is Apache-2.0 licensed. Its upstream CI publishes and signs `master` images and emits provenance attestations.

### Goshtoso

The initial theme baseline is public Goshtoso `v0.2.7`. Goshtoso is MIT licensed. Its supported CLI can extract released theme source, and its public theme catalog contains stable theme keys. The build consumes the selected release only; it does not import components or serve Goshtoso runtime assets.

Goshtoso supplies:

- the complete released theme-token source;
- the theme-key catalog used to generate the client allowlist and selector;
- light/dark token semantics;
- the established `data-theme` and `.dark` contracts.

### AraiHu Assets

The initial asset baseline is public AraiHu Assets `v0.2.3`, verified through the GitHub Release `SHA256SUMS` and the archive's extracted-member `checksums.txt`.

The overlay consumes catalog-addressed files:

- AraiHu adaptive transparent optical logo;
- AraiHu web favicon SVG and 32-pixel PNG fallback;
- the released Heroicons UI sprite entries needed for sun/moon controls;
- required notices and third-party license texts.

AraiHu Assets repository material is Apache-2.0 unless a more specific notice applies. Brand assets retain AraiHu brand terms. Repositories owned by the AraiHu organization are expressly authorized to use and redistribute these assets as part of products and release artifacts. Heroicons remain MIT licensed.

## Architecture decision

### Selected: frontend overlay with security rebuild

The final stage starts from the exact upstream multi-architecture digest. Its
frontend additions are limited to:

- shared `header.html` and `footer.html` overrides;
- generated `static/araihu-styles.css` containing all selected-release Goshtoso themes and the Dex adapter;
- same-origin Lato regular/bold WOFF2 files pinned through `package-lock.json`, used only when a Goshtoso token requests Lato;
- same-origin `appearance.js` and runtime-generated `theme-default.js`;
- optional AraiHu logo/favicon assets and required UI icon assets;
- a small entrypoint wrapper;
- AraiHu overlay notices and licenses.

It also replaces `/usr/local/bin/dex`, `/usr/local/bin/docker-entrypoint`, and
`/usr/local/bin/gomplate` with source-pinned builds from the same locked Dex and
gomplate source revisions. The builder is the digest-pinned Go 1.27.0 Alpine
image. Dex receives no source patch; root `golang.org/x/mod` and the nested API
gRPC dependency are raised explicitly, with resulting transitive Go-module
updates captured in the final module metadata. The source acquisition gate
refuses a future Dex baseline change until these security pins are reviewed.
Gomplate receives no source patch; only its fixed go-git, gRPC, and OpenTelemetry
dependencies are selected. This amendment was required after the original
official binaries failed the HIGH/CRITICAL release gate with detected Go
standard-library vulnerabilities.

It sets `DEX_FRONTEND_DIR=/srv/dex/web`. All flow-specific templates remain the files shipped by the upstream image. The wrapper eventually `exec`s the rebuilt upstream `/usr/local/bin/docker-entrypoint`, preserving upstream argument handling, config templating, PID 1, signals, and shutdown behavior.

### Rejected: full frontend snapshot

Copying all eleven templates into the AraiHu repository would work but would create needless drift. Every upstream wording, field, accessibility, or security change would become a manual merge. Theme source scanning may retain exact upstream templates under test data, but those files are never copied into the final image as overrides.

### Rejected: maintained Dex source fork

A fork is unnecessary because current frontend override hooks cover every required change. A fork would assume responsibility for authentication, MFA, storage, and security patch integration without adding product value.

Recompiling an exact upstream archive with a patched toolchain and dependency
versions does not create a maintained source fork: no Dex source file or
authentication behavior is carried as an AraiHu patch.

## Frontend contract

### Upstream-owned flow markup

The overlay must not replace `login.html`, `password.html`, `approval.html`, `error.html`, `device.html`, `device_success.html`, `oob.html`, `home.html`, `logout.html`, `totp_verify.html`, or `webauthn_verify.html`.

This preserves:

- form methods, targets, hidden authorization-request fields, and approval values;
- input names, IDs, labels, native constraints, autocomplete, and autofocus behavior;
- TOTP QR data and one-time-code semantics;
- WebAuthn begin/finish requests, credential encoding, error handling, and redirects;
- upstream template values and escaping behavior.

### Shared header and footer

The `header.html` override starts from the exact upstream file. It retains Dex's
native `logo` template value and `theme/favicon.png`, so `frontend.logoURL` and
mounted theme assets remain supported. It then adds only:

- optional packaged AraiHu logo and favicon files for explicit configuration;
- the generated theme stylesheet;
- an early same-origin theme-default script;
- the same-origin appearance controller;
- a compact native theme selector;
- a keyboard-operable light/dark icon button with changing accessible label.

The `footer.html` override retains upstream closing structure and adds a compact, non-modal browser-storage notice outside the authentication panel. It offers explicit allow and deny actions. The notice does not block authentication, steal initial focus, or obscure form actions at 390 px.

No flow copy, heading hierarchy, field ordering, task layout, or authentication-state content changes.

## Theme and Tailwind build

### Relationship of sources

- Goshtoso is authoritative for the released multi-theme token catalog and light/dark semantics.
- AraiHu Assets is authoritative for optional organization brand marks,
  platform favicon files, UI icon acquisition, checksums, notices, and brand
  terms.
- The AraiHu theme bundled in Goshtoso is the theme implementation used by the selector. Brand files are not extracted from Goshtoso.
- Dex owns all page and form markup.

### Compilation

The build pins Goshtoso, Tailwind CSS, and the exact upstream template fixture revision. A generation command:

1. verifies the Goshtoso release identity;
2. extracts the supported Goshtoso theme source;
3. reads the public theme catalog and emits a deterministic allowlist;
4. scans the eleven exact upstream templates plus the two shared AraiHu overrides;
5. compiles one `styles.css` containing every released Goshtoso theme and the small Dex class adapter;
6. emits a content manifest and checksums for generated frontend files.

The adapter maps existing Dex selectors to semantic Goshtoso/Tailwind roles. It does not require flow templates to adopt utility-class markup. Generated CSS is committed and checked for drift. The final image contains no Node, Go, Tailwind, or Goshtoso build tooling.

Theme additions or removals come only from an explicit Goshtoso version update. An upstream runtime value cannot synthesize an unknown theme.

### Theme behavior

The root document uses `data-theme="<key>"`; `.dark` selects the dark token set. All eleven pages share the header, so one root assignment propagates tokens everywhere.

The parser-blocking same-origin `theme-default.js` runs before the deferred
appearance controller. It contains the generated theme-key allowlist and
applies the environment default, allowed stored preference, and dark-mode
preference to `<html>` before the first meaningful paint. The deferred
controller then binds the visible controls and repeats the same validated
selection without touching Dex forms.

The visible selector lists the exact generated allowlist. Changing it updates the document immediately. The light/dark button changes `.dark` immediately and updates its accessible name and pressed state. Both controls remain functional without browser storage; denial means changes last only for the current page session.

## Runtime environment contract

### `ARAIHU_DEX_THEME`

`ARAIHU_DEX_THEME` is a non-secret runtime variable owned by the overlay.

- Unset: `araihu`.
- Empty: `araihu`.
- Exact known theme key: use that key as the default.
- Any other value, including whitespace-padded or case-modified values: fail startup before Dex starts.

The process environment is read once before startup effects. The wrapper never logs environment contents or secret-bearing values.

Dex does not expose arbitrary process environment values to `html/template`; it exposes only configured `frontend.extra`. The upstream entrypoint applies gomplate to Dex configuration arguments, not web templates. Therefore a custom entrypoint wrapper is justified.

When `DEX_FRONTEND_DIR` is explicitly empty, the wrapper performs no overlay work and immediately executes the upstream entrypoint. This rollback precedence intentionally bypasses validation of overlay-only settings.

Otherwise, the wrapper performs exactly three jobs:

1. validate `ARAIHU_DEX_THEME` against the generated allowlist;
2. render the root-owned `static/theme-default.template.js` into the writable
   `static/theme-default.js` by replacing its validated default-theme marker;
   repeated starts always render from the immutable template, so a truncated
   served file is repaired before Dex starts;
3. `exec /usr/local/bin/docker-entrypoint "$@"`.

The output file is pre-created and owned by `1001:1001`; the runtime does not need root or a writable web directory. No Go wrapper is introduced. The environment contract belongs to a shell boundary in front of an upstream Go binary, so adding `caarlos0/env` and `envdoc` would add an otherwise unused Go runtime and module solely for one allowlisted value.

## Browser storage and privacy

The overlay uses the established host-scoped preference cookie:

- name: `gt_storage`;
- values: `allowed` or `denied`;
- `Path=/`;
- `Max-Age=15552000` (180 days);
- `SameSite=Lax`;
- no `Domain` attribute;
- no cross-subdomain sharing;
- no analytics or tracking purpose.

If absent, the compact storage notice appears. If allowed, `appearance.js` may persist `theme` and `darkMode` in `localStorage`. If denied, it clears only overlay-owned appearance keys and uses the environment default plus `prefers-color-scheme`. If cookie or local storage access throws, the page remains usable, uses in-memory state, and emits no uncaught error.

Dex session, connector, CSRF, OAuth, and MFA cookies or query values remain exclusively upstream-owned. The overlay never reads, writes, aliases, or clears them.

## JavaScript and CSP

Custom JavaScript is limited to:

- validated default-theme bootstrap;
- theme selection;
- light/dark selection;
- consent actions and persistence.

It is plain same-origin JavaScript. It neither intercepts forms nor listens to authentication events. No custom script calls Dex authentication, TOTP, or WebAuthn endpoints.

New JavaScript is external, so it does not add an inline-script CSP requirement. Dex `master` itself uses inline scripts in password, home, logout, and WebAuthn surfaces, and WebAuthn uses an inline event handler. A CSP compatible with unchanged upstream behavior must account for those scripts. TOTP enrollment also requires `img-src data:` for its base64 QR image. The test environment exercises the deployment CSP and reports the precise upstream-required exceptions; the overlay must not broaden them further.

## Upstream pinning and updates

A single machine-readable lock records:

- upstream Dex commit;
- upstream multi-architecture image digest;
- Goshtoso version and source identity;
- AraiHu Assets version, archive digest, and member checksum identity;
- Tailwind version and package integrity;
- generated theme allowlist digest.

CI verifies the upstream OCI `org.opencontainers.image.revision` label equals the locked commit. It verifies the upstream signature and provenance against the official Dex GitHub Actions identity before building.

A weekly scheduled workflow and manual dispatch run the same update command. The approved prerelease lock is the initial baseline; the command then resolves the current Dex `master` commit and matching image digest, reads the official `org.opencontainers.image.version` pseudo-version, refreshes non-runtime template fixtures, updates the lock to that version plus digest, regenerates assets, and opens a pull request. It never merges, tags, publishes, or changes homelab state.

An update pull request fails closed when:

- commit and digest do not match;
- the required-template inventory changes unexpectedly;
- a shared header/footer patch no longer applies cleanly;
- a flow template would become an overlay file;
- the WebAuthn script differs without refreshed semantic evidence;
- generated output drifts;
- screenshots or accessibility gates fail.

## OCI build and release

### Platforms

The release index contains exactly:

- `linux/amd64`;
- `linux/arm64`.

Frontend generation runs once on the build platform. Both target manifests receive identical generated frontend bytes. The final image remains Alpine-based because the validated shell wrapper requires `/bin/sh`; no package installation occurs in the final stage.

### Naming and tags

The repository publishes only to `ghcr.io/araihu/dex`.

Stable release publication creates:

- `vX.Y.Z`;
- `X.Y`;
- `X`;
- `latest`.

There is no AraiHu `master`, `edge`, or per-PR registry tag. Pull requests build locally in CI without publication. OCI labels record the AraiHu source URL and revision, upstream Dex source commit and base digest, Goshtoso version, AraiHu Assets version, license set, creation time, and version.

### Evidence

Each stable release produces:

- BuildKit/GitHub provenance for the multi-architecture index;
- SPDX JSON SBOM for the final image;
- keyless Cosign signature bound to the release workflow identity;
- generated frontend manifest and checksums as workflow artifacts;
- screenshot matrix as workflow artifacts;
- vulnerability scan report.

The OCI creation label and BuildKit `SOURCE_DATE_EPOCH` derive from the exact
release commit's committer timestamp, not the runner wall clock. Trivy is a
fail-closed `HIGH,CRITICAL` gate and ignores only unfixed findings, with its
SARIF output limited to those severities and retained as release evidence.
Both architecture scans target the exact platform manifest digests extracted
from the published immutable candidate index. Evidence collection and upload
complete before stable aliases are promoted.

Determinism is scoped to generated frontend bytes and the platform image
manifests/configuration produced from the locked source and source-derived
timestamp. BuildKit provenance and SBOM attestations are attached to the image
index and may contain invocation-specific envelope metadata on independent
rebuilds; verification binds each attestation to the exact platform subject
digest rather than comparing those envelopes byte-for-byte.

The `candidate-${GITHUB_SHA}` reference is temporary for the publication flow
but retained as an immutable audit alias after promotion. GHCR deletion is
package-version or manifest-digest scoped; because stable aliases share the
candidate digest, deleting that reference could delete the stable aliases. No
candidate cleanup mutation is therefore attempted.

Release workflow permissions are limited to:

- `contents: read`;
- `packages: write`;
- `id-token: write`;
- `attestations: write`.

Pull-request CI uses `contents: read` and `packages: read`. The update workflow alone uses `contents: write` and `pull-requests: write`. No workflow receives deployment credentials.

Creating a Git tag and allowing its publication workflow requires explicit user authorization. A green pull request or local build does not grant publication authority.

## Testing and acceptance

### Static and generation checks

- Lock schema and value validation.
- Archive and member checksum verification.
- Generated-file drift check.
- Theme allowlist matches the selected Goshtoso release.
- Every theme emits required semantic variables.
- Tailwind source scan includes every exact upstream template fixture and shared override.
- Only the approved shared frontend paths are added to the upstream filesystem.
- Shell lint and entrypoint tests cover unset, empty, valid, malformed, padded, and unknown `ARAIHU_DEX_THEME` values.
- Multi-architecture index contains only amd64 and arm64.
- OCI base revision label matches the lock.

### Template and semantic regression

Tests run the real derived Dex image with an isolated configuration, mock connector, password database, sessions, TOTP, and WebAuthn. They assert:

- all eleven templates render through actual routes;
- form methods, actions, hidden fields, values, and native constraints remain upstream-compatible;
- consent with scopes and without scopes remains correct;
- password errors preserve username, focus, and native form behavior;
- TOTP enrollment, verification, and invalid-code states preserve QR, field, and submission semantics;
- WebAuthn registration and login use upstream begin/finish endpoints and a browser virtual authenticator;
- working, cancellation, timeout, security, and server-error recovery remain visible and retryable;
- home, logout, device, OOB, and error routes retain their upstream behavior;
- custom scripts never submit or mutate authentication forms.

### Theme and storage regression

- Default environment value and every allowlisted theme compute nonempty semantic styles on every page.
- Theme selector and dark-mode control work with keyboard and pointer input.
- `gt_storage` absent, allowed, and denied states behave as specified.
- Throwing cookie and `localStorage` access falls back without page errors.
- Denied storage changes current-page appearance without persistence.
- Allowed storage restores theme and dark mode before first meaningful paint.
- A delayed appearance controller cannot produce a first-frame flash because
  the parser-blocking bootstrap applies allowed stored preferences first.
- Invalid stored theme falls back to the validated environment default.

### Visual evidence

For the AraiHu default, Playwright captures every page and meaningful state at 390 px and 1440 px in light and dark mode. Dynamic TOTP QR pixels are masked while QR presence, size, alt text, and surrounding semantics remain asserted.

Every other Goshtoso theme captures login at 390 px and 1440 px in light and dark mode. All pages also run computed-style smoke checks for every theme. AraiHu screenshots are committed visual-regression baselines; the full matrix is retained as CI artifacts.

Acceptance also requires:

- visible keyboard focus;
- correct accessible labels, names, roles, and states;
- no critical Axe violations;
- no unexpected browser console or page errors;
- adequate control and text contrast in supported light/dark combinations;
- no content clipping or consent-banner obstruction at 390 px;
- reduced-motion compatibility.

## Rollback

Rollback has no data migration or identity transformation.

1. Set `DEX_FRONTEND_DIR=` to make the same Dex binary use its embedded upstream frontend.
2. If the overlay image itself is suspect, restore the exact previously pinned
   official prerelease image and digest from `versions.env`.
3. If only the configured default theme is invalid, remove `ARAIHU_DEX_THEME` or set it to `araihu`.

Rollback tests run login, consent, TOTP, WebAuthn, home, and logout with
`DEX_FRONTEND_DIR=` on the derived image and repeat the same flow against the
exact pinned official image. The wrapper bypass test also confirms that an
invalid overlay theme cannot block the embedded upstream frontend.

Rollback verification covers login, consent, TOTP, WebAuthn, home, and logout against the embedded upstream frontend. The homelab adoption plan must retain the prior image digest until its own separately authorized rollout is accepted.

## Repository and lifecycle boundaries

The local repository is initialized at `/Users/guilhermecastro/repos/araihu/dex`
with the established AraiHu Git identity and conventions. Public visibility,
creation of `github.com/araihu/dex`, initial `main` push, and GHCR publication
were explicitly authorized on 2026-08-25. Tag `v0.0.1` was explicitly selected
on 2026-08-26.

Separate explicit approvals are required for:

- creating any later tag or a GitHub Release;
- editing or deploying the homelab.

## Acceptance criteria

The project is implementation-complete only when:

1. The derived image starts from the exact locked official Dex prerelease tag
   and digest, then rebuilds only the three Go binaries from locked sources.
2. All eleven upstream pages retain authentication semantics and receive the selected Goshtoso theme.
3. AraiHu is the default and every selected-release Goshtoso theme is client-selectable.
4. `ARAIHU_DEX_THEME`, consent, no-storage fallback, and dark mode behave exactly as documented.
5. TOTP and WebAuthn run through the unmodified upstream logic and JavaScript.
6. amd64 and arm64 images pass fresh tests and share identical frontend assets.
7. SBOM, provenance, signature, license notices, and screenshot evidence are generated.
8. Both rollback paths are tested.
9. No homelab, GitHub repository, remote ref, release, or registry state changes occur without the corresponding explicit authorization.
