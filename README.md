# AraiHu Dex

Thin AraiHu frontend overlay for a locked official Dex prerelease image. It
preserves Dex authentication behavior, flow templates, TOTP, and WebAuthn logic
while adding released Goshtoso themes and AraiHu assets.

The approved design and implementation plan are in:

- [`docs/superpowers/specs/2026-08-25-araihu-dex-container-design.md`](docs/superpowers/specs/2026-08-25-araihu-dex-container-design.md)
- [`docs/superpowers/plans/2026-08-25-araihu-dex-container-implementation.md`](docs/superpowers/plans/2026-08-25-araihu-dex-container-implementation.md)

## Lifecycle gates

Repository visibility must be explicitly chosen before creating a GitHub
repository, and creating `github.com/araihu/dex` then requires separate
explicit approval. No branch is pushed without separate explicit approval. No
tag or GitHub Release is created without separate explicit approval. No GHCR
image is published without separate explicit approval. No homelab file is
edited or deployment performed without separate explicit approval.

Green tests, a local build, review approval, or this repository's existence do
not authorize any of those actions.

The release workflow being present grants no lifecycle authority. Repository
creation and visibility, the first branch push, creation/push of a release tag,
and GHCR publication are separate external approvals. Because pushing an
accepted tag starts publication, both tag and GHCR publication approval must
exist before that push.

## Verified source cache

[`versions.env`](versions.env) is the single source lock. It pins the approved
Dex commit/archive, Goshtoso module/theme/catalog, AraiHu Assets release and
member manifest, plus the frontend tool baselines. The POSIX acquisition
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

## CI and upstream updates

Pull requests and `main` pushes run source, generation, shell, Node,
multi-architecture build, filesystem-overlay, real-image, visual,
accessibility, and vulnerability checks. CI builds only into the local Docker
daemon, OCI files, and local BuildKit caches. It has no registry login, image
publication, tag, attestation generation, or signing step.

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

The unexecuted release workflow accepts only canonical stable `vX.Y.Z` tag
pushes. It publishes only `ghcr.io/araihu/dex` with `vX.Y.Z`, `X.Y`, `X`, and
`latest`; prerelease, `master`, `edge`, and pull-request tags are rejected. Its
release index is exactly `linux/amd64,linux/arm64` and carries locked source and
license labels. Before registry login it reruns trust, generation, policy,
real-image, visual, local multi-architecture OCI, and vulnerability gates.

An authorized publication adds BuildKit provenance and an SPDX JSON SBOM,
GitHub build provenance, and a keyless Cosign signature bound to
`.github/workflows/release.yml` at the exact release tag. The workflow retains
the OCI manifest and checksum, frontend checksums, SBOM, provenance, scan, and
screenshot evidence.

The OCI creation label and `SOURCE_DATE_EPOCH` come from the release commit's
committer timestamp, so rerunning a release for the same source does not add a
wall-clock value. Trivy is a fail-closed `HIGH,CRITICAL` gate; it ignores only
unfixed findings (`ignore-unfixed: true`) and retains the SARIF report as
evidence.

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
stable tag mapping, registry evidence, GitHub attestation, and workflow-bound
signature:

```sh
scripts/verify-release.sh remote ghcr.io/araihu/dex@sha256:...
```

Remote mode is intentionally deferred until an image exists. It is read-only
but requires Docker Buildx, `jq`, Python, Cosign, GitHub CLI, registry access,
and GitHub attestation access; it never logs in, pushes, signs, tags, or mutates
registry or GitHub state itself.

## License and notices

This overlay is licensed under [Apache-2.0](LICENSE). See [NOTICE](NOTICE) for
Dex, Goshtoso, AraiHu Assets, AraiHu brand terms, and Heroicons notices.
