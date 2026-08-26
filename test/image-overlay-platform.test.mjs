import assert from 'node:assert/strict';
import { chmod, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '..');

test('selects the upstream child manifest matching the derived image platform', async (t) => {
  const state = await mkdtemp(path.join(tmpdir(), 'araihu-dex-platform-'));
  t.after(() => rm(state, { recursive: true, force: true }));

  const bin = path.join(state, 'bin');
  const log = path.join(state, 'docker.log');
  const count = path.join(state, 'create-count');
  await mkdir(bin);

  const arm64Digest = `sha256:${'a'.repeat(64)}`;
  const manifest = JSON.stringify({
    mediaType: 'application/vnd.oci.image.index.v1+json',
    manifests: [
      {
        digest: `sha256:${'b'.repeat(64)}`,
        platform: { os: 'linux', architecture: 'amd64' },
      },
      {
        digest: arm64Digest,
        platform: { os: 'linux', architecture: 'arm64' },
      },
    ],
  });

  const docker = path.join(bin, 'docker');
  await writeFile(
    docker,
    `#!/bin/sh
set -eu
case "\${1:-}:\${2:-}:\${3:-}" in
  image:inspect:*) printf '%s\\n' arm64 ;;
  buildx:imagetools:inspect) printf '%s\\n' "$FAKE_MANIFEST" ;;
  create:--platform:*)
    ref=
    for arg do ref=$arg; done
    printf '%s\\n' "$ref" >>"$FAKE_DOCKER_LOG"
    current=0
    [ ! -f "$FAKE_DOCKER_COUNT" ] || current=$(cat "$FAKE_DOCKER_COUNT")
    current=$((current + 1))
    printf '%s\\n' "$current" >"$FAKE_DOCKER_COUNT"
    [ "$current" -eq 1 ] || exit 91
    printf '%s\\n' upstream-container
    ;;
  rm:-f:*) exit 0 ;;
  *) printf 'unexpected docker call: %s\\n' "$*" >&2; exit 88 ;;
esac
`,
  );
  await chmod(docker, 0o755);

  const result = spawnSync('sh', ['test/image-overlay_test.sh', 'derived:test'], {
    cwd: root,
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      FAKE_DOCKER_COUNT: count,
      FAKE_DOCKER_LOG: log,
      FAKE_MANIFEST: manifest,
    },
  });

  assert.notEqual(result.status, 0, 'fixture must stop after upstream selection');
  const [selected] = (await readFile(log, 'utf8')).trim().split('\n');
  assert.match(selected, /^ghcr\.io\/dexidp\/dex:[^@]+@sha256:[0-9a-f]{64}$/);
  assert.equal(selected.slice(selected.lastIndexOf('@') + 1), arm64Digest);
});
