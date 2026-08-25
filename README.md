# AraiHu Dex

Thin AraiHu frontend overlay for the official Dex `master` image. It preserves
Dex authentication behavior, flow templates, TOTP, and WebAuthn logic while
adding released Goshtoso themes and AraiHu assets.

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

## CI and upstream updates

Pull requests and `main` pushes run source, generation, shell, Node,
multi-architecture build, filesystem-overlay, real-image, visual,
accessibility, and vulnerability checks. CI builds only into the local Docker
daemon, OCI files, and local BuildKit caches. It has no registry login, image
publication, tag, attestation generation, or signing step.

Verify the locked official Dex image's revision, Cosign identity, and SLSA
provenance without preparing an update:

```sh
scripts/update-lock.sh --verify-lock
```

To prepare the current verified Dex `master` commit locally, install
dependencies and the Playwright browser first, ensure `gh`, `cosign`, Docker
Buildx, Go, Node, `jq`, and `curl` are available, then run:

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

The weekly/manual upstream workflow runs preparation plus every CI gate in a
credentialless, read-only job. Only after those gates pass does a separate
write-scoped job validate the checksum-bound patch artifact against the exact
verified base/result, configure credentials, and create an update branch and
pull request with GitHub's token and `gh`. A pull request still requires human
screenshot review and grants no merge, release, publication, or deployment
authority.

## License and notices

This overlay is licensed under [Apache-2.0](LICENSE). See [NOTICE](NOTICE) for
Dex, Goshtoso, AraiHu Assets, AraiHu brand terms, and Heroicons notices.
