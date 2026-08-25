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

## License and notices

This overlay is licensed under [Apache-2.0](LICENSE). See [NOTICE](NOTICE) for
Dex, Goshtoso, AraiHu Assets, AraiHu brand terms, and Heroicons notices.
