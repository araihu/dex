# AraiHu Dex

AraiHu-maintained frontend overlay for a locked official Dex prerelease image.
It preserves Dex authentication behavior, native branding hooks, flow
templates, TOTP, and WebAuthn logic while adding released Goshtoso themes and
optional AraiHu assets. The final stage remains based on the official image,
but rebuilds its Dex, entrypoint, and gomplate binaries with Go 1.27.0 to avoid
vulnerabilities detected in the original toolchain build.

The approved design and implementation plan are in:

- [`docs/superpowers/specs/2026-08-25-araihu-dex-container-design.md`](docs/superpowers/specs/2026-08-25-araihu-dex-container-design.md)
- [`docs/superpowers/plans/2026-08-25-araihu-dex-container-implementation.md`](docs/superpowers/plans/2026-08-25-araihu-dex-container-implementation.md)

## Lifecycle gates

Public visibility, creation of `github.com/araihu/dex`, initial `main` push,
and GHCR publication were explicitly authorized on 2026-08-25. Tag `v0.0.1`
was explicitly selected on 2026-08-26. A GitHub Release remains a separate
lifecycle action and is not part of this repository workflow. No homelab file
is edited or deployment performed without separate explicit approval.

Green tests, a local build, review approval, or this repository's existence do
not authorize any of those actions.

The release workflow being present grants no lifecycle authority. Repository
creation and visibility, the first branch push, creation/push of a release tag,
and GHCR publication are separate external approvals. Because pushing an
accepted tag starts publication, both tag and GHCR publication approval must
exist before that push.

## Verified source cache

[`versions.env`](versions.env) is the upstream/frontend source lock. It pins
the approved Dex commit/archive and expected dependency baselines, Goshtoso
module/theme/catalog, AraiHu Assets release and member manifest, plus the
frontend tool baselines. The Dockerfile separately digest/checksum-pins its Go
builder and gomplate source and version-pins rebuild dependencies.
`package-lock.json` also
pins the exact Fontsource Lato package and integrity used for deterministic
AraiHu-theme typography. The POSIX acquisition
boundary verifies every checksum before writing the cache:

```sh
scripts/fetch-sources.sh
```

Use `FETCH_CACHE` for an alternate cache and `VERSIONS_FILE` for an isolated
fixture lock. The script never reads sibling checkouts or copies unverified
source files.

The current base is exactly
`ghcr.io/dexidp/dex:v2.46.0-20260806171424-ab64ed77@sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b`.
The generic `:master` tag is not an accepted build contract.
Lock-only verification accepts that one immutable prerelease as an alias for
the same official `master`-workflow signature and provenance identity. Update
preparation accepts this prerelease as its initial baseline, resolves the next
verified `master` commit and digest, reads the official
`org.opencontainers.image.version` pseudo-version, and writes that version tag
with the digest as the lock. It never follows the mutable tag in the
Dockerfile.

Dex and its entrypoint are rebuilt from that exact source archive. Gomplate is
rebuilt from its exact `v5.2.0` commit. Neither source tree carries an AraiHu
patch; only dependencies with published fixes are raised before compilation.
The image carries the Go, musl, gomplate, and downloaded Go-module license
inventory used by those static binaries.
To restore the original binaries, run the pinned official image directly.
Setting `DEX_FRONTEND_DIR` empty restores only its embedded frontend.

The overlay keeps Dex's native logo and favicon by default. Its header still
uses Dex's `logo` value, so `frontend.logoURL` continues to work from the
normal Dex configuration (including a mounted, environment-templated config).
Theme logo and favicon files may also be replaced through the existing Dex
theme mount paths. The packaged AraiHu files remain available under
`/srv/dex/web/static/` for an explicit branding configuration.

The header's parser-blocking `theme-default.js` applies the selected default
and allowed stored appearance before the deferred control script runs. The
control script then handles theme selection, dark mode, and the `gt_storage`
consent boundary; it never submits or changes a Dex authentication form.
The entrypoint renders that file from a root-owned template on every start.

## CI and upstream updates

Pull requests and `main` pushes run source, generation, shell, Node,
multi-architecture build, filesystem-overlay, real-image, visual,
accessibility, and vulnerability checks. CI builds only into the local Docker
daemon, OCI files, and local BuildKit caches. It has no registry login, image
publication, tag, attestation generation, or signing step.

Committed screenshot baselines are canonical Ubuntu/Playwright output used by
CI. The AraiHu theme's Lato token resolves to two same-origin, OFL-licensed
WOFF2 files generated from the pinned Fontsource package. This avoids host font
drift without changing Goshtoso tokens; themes that do not request Lato remain
untouched.

Verify the locked official Dex image's revision, Cosign identity, and SLSA
provenance from public registry data, without a GitHub token or update
preparation:

```sh
scripts/update-lock.sh --verify-lock
```

To prepare the next verified Dex `master` commit locally, install
dependencies and the Playwright browser first, ensure `cosign`, Docker Buildx,
Go, Node, `jq`, and `curl` are available, then run:

```sh
npm ci
npx playwright install chromium
scripts/update-lock.sh
```

The update command works in a staged tree and copies changes back only after
signature/provenance, exact template inventory, shared-template rebase,
unchanged WebAuthn JavaScript, generation, filesystem-overlay, semantic,
visual, and accessibility checks pass. It updates local locks, fixtures,
generated files, and `.cache/update-report.md`; it never commits, pushes,
opens a pull request, tags, publishes, or touches homelab state.
The report target is fixed to that repository-owned path; outside paths and
symlinked report files or parents are rejected before preparation.

The weekly/manual upstream workflow runs preparation plus every CI gate with
only `contents: read` and `packages: read`. Its checkout uses the explicit
job-scoped `${{ github.token }}` and `persist-credentials: false`, so private
repositories work without retaining credentials. Cosign trust verification
remains public and token-free. A second `contents: read` job downloads the
immutable artifact ID and validates its checksums, exact base/result, patch,
path allowlist, and report/lock consistency. Only after that validation succeeds
can a separate write-scoped job start. It downloads the immutable-ID artifact
and rechecks the full artifact/base/hash/path/report binding before checkout,
then checks out without persisted credentials, applies and rechecks the patch,
configures Git credentials, and creates the update branch and pull request with
GitHub's token and `gh`. A pull request still requires human screenshot review
and grants no merge, release, publication, or deployment authority.

## Prepared release workflow

The release workflow accepts only canonical stable `vX.Y.Z` tag
pushes. It publishes only `ghcr.io/araihu/dex` with `vX.Y.Z`, `vX.Y`, `vX`, and
`latest`; prerelease, `master`, `edge`, and pull-request tags are rejected. Its
release image is exactly `linux/amd64` and carries locked source and license
labels. Before registry login it reruns trust, generation, policy, real-image,
and visual gates. It then publishes only the immutable candidate reference and
scans its exact manifest before any stable tag is promoted.

An authorized publication adds a keyless Cosign signature bound to
`.github/workflows/release.yml` at the exact release tag. The workflow retains
the OCI manifest and checksum, frontend checksums, scan, and screenshot
evidence.

The OCI creation label and `SOURCE_DATE_EPOCH` come from the release commit's
committer timestamp, so rerunning a release for the same source does not add a
wall-clock value. Trivy v0.74.0 is a fail-closed `HIGH,CRITICAL` gate; it ignores
only unfixed findings (`ignore-unfixed: true`), limits SARIF to those
severities, scans the exact published candidate digest, and retains the report
as evidence.

Reproducibility covers the generated frontend bytes. The amd64 build uses
pinned source/toolchain inputs and exposes its exact result through the OCI
digest.

The candidate reference is retained as an immutable audit alias after its
temporary publication use (`candidate-${GITHUB_SHA}`). GHCR deletion is scoped
to a package version or manifest digest; because stable aliases share the
candidate digest, deleting the candidate could delete stable aliases. The
workflow therefore performs no candidate cleanup mutation.

Verify a candidate OCI archive without registry access or publication:

```sh
scripts/verify-release.sh local path/to/release.oci.tar
```

After a separately authorized publication, verify its exact GHCR subject,
stable tag mapping, labels, platform, and workflow-bound signature:

```sh
scripts/verify-release.sh remote ghcr.io/araihu/dex@sha256:...
```

Remote mode is intentionally deferred until an image exists. It is read-only
but requires Docker Buildx, `jq`, Python, Cosign, and registry access; it never
logs in, pushes, signs, tags, or mutates registry or GitHub state itself.

Rollback verification runs `test/rollback.spec.ts` with `DEX_FRONTEND_DIR=` on
the derived image and on the exact pinned upstream image before any homelab
adoption decision.

## License and notices

This overlay is licensed under [Apache-2.0](LICENSE). See [NOTICE](NOTICE) for
Dex, Goshtoso, AraiHu Assets, AraiHu brand terms, and Heroicons notices.
