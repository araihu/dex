#!/bin/sh
set -eu

die() {
	printf '%s\n' "release-policy-test: $*" >&2
	exit 1
}

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
workflow=$repo/.github/workflows/release.yml
dockerfile=$repo/Dockerfile
verifier=$repo/scripts/verify-release.sh

[ -f "$workflow" ] || die "workflow not found: $workflow"
[ -x "$verifier" ] || die "release verifier not executable: $verifier"
command -v ruby >/dev/null 2>&1 || die 'ruby is required'
command -v python3 >/dev/null 2>&1 || die 'python3 is required'

state=$(mktemp -d "${TMPDIR:-/tmp}/araihu-dex-release-policy.XXXXXX")
cleanup() {
	rm -rf "$state"
}
trap cleanup EXIT HUP INT TERM

check_policy() {
	ruby - "$1" "$2" "$repo/versions.env" <<'RUBY'
require 'yaml'

workflow_path, dockerfile_path, versions_path = ARGV
source = File.read(workflow_path)
workflow = YAML.safe_load(source, aliases: true)
abort 'workflow must be a mapping' unless workflow.is_a?(Hash)

trigger = workflow['on'] || workflow[true]
expected_trigger = {
  'push' => {
    'tags' => ['v[0-9]+.[0-9]+.[0-9]+'],
  },
}
abort 'release trigger must contain only stable vX.Y.Z tag pushes' unless trigger == expected_trigger

expected_permissions = {
  'contents' => 'read',
  'packages' => 'write',
  'id-token' => 'write',
  'attestations' => 'write',
}
abort 'release permissions differ from the exact allowlist' unless workflow['permissions'] == expected_permissions
abort 'release image is not the sole approved GHCR repository' unless workflow.dig('env', 'IMAGE') == 'ghcr.io/araihu/dex'
abort 'release platforms differ from the exact pair' unless workflow.dig('env', 'PLATFORMS') == 'linux/amd64,linux/arm64'

jobs = workflow['jobs']
abort 'release workflow must have exactly one job' unless jobs.is_a?(Hash) && jobs.keys == ['release']
job = jobs['release']
abort 'job-level permissions are forbidden' if job.key?('permissions')
abort 'deployment environments are forbidden' if job.key?('environment')
steps = job['steps']
abort 'release steps missing' unless steps.is_a?(Array)

def step(steps, id)
  found = steps.select { |candidate| candidate['id'] == id }
  abort "release step #{id.inspect} must occur exactly once" unless found.length == 1
  found.first
end

action_lines = source.lines.grep(/^\s*uses:/)
abort 'release workflow must use pinned actions' if action_lines.empty?
action_lines.each do |line|
  next if line.match?(/uses:\s+[^\s#]+@[0-9a-f]{40}\s+#\s+v[0-9]+\.[0-9]+\.[0-9]+\s*$/)
  abort "action is not immutable SHA-pinned with a version comment: #{line.strip}"
end

checkout = step(steps, 'checkout')
abort 'checkout action missing' unless checkout['uses'].start_with?('actions/checkout@')
abort 'checkout credentials must not persist' unless checkout.dig('with', 'persist-credentials') == false
abort 'checkout must use the job-scoped token explicitly' unless checkout.dig('with', 'token') == '${{ github.token }}'

metadata = step(steps, 'release')
metadata_run = metadata['run'].to_s
[
  '^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$',
  'ghcr.io/araihu/dex',
  ':latest',
  'org.opencontainers.image.created=',
  'org.opencontainers.image.revision=',
  'org.opencontainers.image.version=',
  'org.opencontainers.image.source=',
  'org.opencontainers.image.licenses=',
  'io.araihu.dex.upstream.revision=',
  'io.araihu.dex.upstream.digest=',
  'io.araihu.dex.goshtoso.version=',
  'io.araihu.dex.assets.version=',
].each { |fragment| abort "release metadata missing #{fragment}" unless metadata_run.include?(fragment) }

trust = step(steps, 'trust')
abort 'locked upstream trust verification missing' unless trust['run'].to_s.include?('scripts/update-lock.sh --verify-lock')

local_oci = step(steps, 'local_oci')
local_run = local_oci['run'].to_s
abort 'local candidate lacks exact platforms' unless local_oci.dig('env', 'PLATFORMS') == '${{ env.PLATFORMS }}'
abort 'local candidate lacks maximum provenance' unless local_run.include?('--provenance=mode=max')
abort 'local candidate lacks embedded SBOM' unless local_run.include?('--sbom=true')
abort 'local candidate is not an OCI archive' unless local_run.include?('type=oci,dest=$RUNNER_TEMP/release.oci.tar')

verify_local = step(steps, 'verify_local')
abort 'local OCI verification missing' unless verify_local['run'].to_s.include?('scripts/verify-release.sh local "$RUNNER_TEMP/release.oci.tar"')

scan = step(steps, 'scan')
abort 'vulnerability scan action missing' unless scan['uses'].start_with?('aquasecurity/trivy-action@')
abort 'scan report must be retained as SARIF' unless scan.dig('with', 'format') == 'sarif' && scan.dig('with', 'output') == 'release-evidence/vulnerability-report.sarif'

login = step(steps, 'login')
abort 'GHCR login action missing' unless login['uses'].start_with?('docker/login-action@')
abort 'registry login must target GHCR' unless login.dig('with', 'registry') == 'ghcr.io'
abort 'registry login must use the actor' unless login.dig('with', 'username') == '${{ github.actor }}'
abort 'registry login must use the job-scoped token' unless login.dig('with', 'password') == '${{ github.token }}'

publish = step(steps, 'publish')
abort 'publish action missing' unless publish['uses'].start_with?('docker/build-push-action@')
expected_publish = {
  'context' => '.',
  'platforms' => '${{ env.PLATFORMS }}',
  'push' => true,
  'tags' => '${{ steps.release.outputs.tags }}',
  'labels' => '${{ steps.release.outputs.labels }}',
  'provenance' => 'mode=max',
  'sbom' => true,
}
expected_publish.each do |key, value|
  abort "publish #{key} policy mismatch" unless publish.dig('with', key) == value
end

attest = step(steps, 'attest')
abort 'GitHub build provenance attestation missing' unless attest['uses'].start_with?('actions/attest-build-provenance@')
abort 'attestation subject name mismatch' unless attest.dig('with', 'subject-name') == '${{ env.IMAGE }}'
abort 'attestation subject digest mismatch' unless attest.dig('with', 'subject-digest') == '${{ steps.publish.outputs.digest }}'
abort 'attestation must be pushed with the image' unless attest.dig('with', 'push-to-registry') == true
abort 'artifact metadata permission expansion is forbidden' unless attest.dig('with', 'create-storage-record') == false

sign = step(steps, 'sign')
abort 'keyless digest signing missing' unless sign['run'].to_s.include?('cosign sign --yes "$IMAGE@$DIGEST"')
abort 'signature must bind the published digest' unless sign.dig('env', 'DIGEST') == '${{ steps.publish.outputs.digest }}'

verify_remote = step(steps, 'verify_remote')
abort 'remote signature/evidence verification missing' unless verify_remote['run'].to_s.include?('scripts/verify-release.sh remote "$IMAGE@$DIGEST"')

evidence = step(steps, 'evidence')
evidence_run = evidence['run'].to_s
abort 'release index evidence missing' unless evidence_run.include?('release-manifest.json')
abort 'release manifest checksum missing' unless evidence_run.include?('release-manifest.json.sha256')
abort 'release SBOM evidence missing' unless evidence_run.include?('sbom.spdx.json')
abort 'release provenance evidence missing' unless evidence_run.include?('provenance.slsa.json')

upload = step(steps, 'upload')
upload_paths = upload.dig('with', 'path').to_s
%w[release-evidence/ web/manifest.sha256 test/screenshots/araihu/ test-results/ playwright-report/].each do |path|
  abort "artifact upload misses #{path}" unless upload_paths.include?(path)
end

ids = steps.map { |candidate| candidate['id'] }.compact
%w[trust verify_local scan].each do |id|
  abort "#{id} must run before registry login" unless ids.index(id) < ids.index('login')
end
%w[attest sign verify_remote evidence upload].each do |id|
  abort "#{id} must run after publication" unless ids.index(id) > ids.index('publish')
end

serialized = workflow.to_s
abort 'pull-request publication is forbidden' if serialized.match?(/pull_request|refs\/pull/)
abort 'mutable release tags are forbidden' if serialized.match?(/(?:^|[^a-z])(?:master|edge)(?:[^a-z]|$)/i)
abort 'secrets are forbidden in release workflow' if serialized.include?('secrets.')
abort 'deployments are forbidden in release workflow' if serialized.match?(/deploy|homelab/i)

locked_image = File.foreach(versions_path).find { |line| line.start_with?('DEX_IMAGE=') }&.split('=', 2)&.last&.strip
abort 'locked Dex image missing' unless locked_image
expected_locked_image = 'ghcr.io/dexidp/dex:v2.46.0-20260806171424-ab64ed77@sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b'
abort 'Dex image lock must use the approved immutable prerelease' unless locked_image == expected_locked_image
from = File.foreach(dockerfile_path).find { |line| line.start_with?('FROM ') }&.split&.fetch(1, nil)
abort 'Dockerfile base must equal the immutable lock' unless from == locked_image
abort 'Dockerfile base must reject the generic master tag' unless from == expected_locked_image
RUBY
}

mutate() {
	python3 - "$1" "$2" "$3" "$4" <<'PY'
import pathlib
import sys

source, target, old, new = sys.argv[1:]
old = old.replace(r'\n', '\n')
new = new.replace(r'\n', '\n')
text = pathlib.Path(source).read_text()
if text.count(old) != 1:
    raise SystemExit(f"mutation source count for {old!r}: {text.count(old)}")
pathlib.Path(target).write_text(text.replace(old, new))
PY
}

assert_workflow_rejected() {
	name=$1
	old=$2
	new=$3
	mutated=$state/$name.yml
	mutate "$workflow" "$mutated" "$old" "$new"
	if check_policy "$mutated" "$dockerfile" >/dev/null 2>&1; then
		die "policy accepted $name mutation"
	fi
}

check_policy "$workflow" "$dockerfile"
assert_workflow_rejected trigger "'v[0-9]+.[0-9]+.[0-9]+'" "'*'"
assert_workflow_rejected pull_request 'on:\n  push:' 'on:\n  pull_request:\n  push:'
assert_workflow_rejected platform 'linux/amd64,linux/arm64' 'linux/amd64,linux/arm64,linux/s390x'
assert_workflow_rejected permission 'contents: read' 'contents: write'
assert_workflow_rejected action_pin 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' 'actions/checkout@v7 # v7.0.1'
assert_workflow_rejected image 'IMAGE: ghcr.io/araihu/dex' 'IMAGE: ghcr.io/araihu/dex-other'
assert_workflow_rejected edge ':latest' ':edge'
assert_workflow_rejected provenance 'provenance: mode=max' 'provenance: false'
assert_workflow_rejected sbom 'sbom: true' 'sbom: false'
assert_workflow_rejected signing 'cosign sign --yes "$IMAGE@$DIGEST"' 'true # signature removed'
assert_workflow_rejected verification 'scripts/verify-release.sh remote "$IMAGE@$DIGEST"' 'true # verification removed'

mutable_dockerfile=$state/Dockerfile.mutable
locked_image=$(sed -n 's/^DEX_IMAGE=//p' "$repo/versions.env")
mutate "$dockerfile" "$mutable_dockerfile" "$locked_image" 'ghcr.io/dexidp/dex:master'
if check_policy "$workflow" "$mutable_dockerfile" >/dev/null 2>&1; then
	die 'policy accepted mutable base image'
fi

ruby - "$workflow" > "$state/release-step.sh" <<'RUBY'
require 'yaml'
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
steps = workflow.fetch('jobs').fetch('release').fetch('steps')
puts steps.find { |candidate| candidate['id'] == 'release' }.fetch('run')
RUBY

run_release_step() {
	ref_type=$1
	ref_name=$2
	output=$3
	release_sha=${4:-$(git -C "$repo" rev-parse HEAD)}
	: > "$output"
	GITHUB_REF_TYPE=$ref_type \
		GITHUB_REF_NAME=$ref_name \
		GITHUB_SHA=$release_sha \
		GITHUB_OUTPUT=$output \
		bash "$state/release-step.sh"
}

run_release_step tag v1.2.3 "$state/release-output"
grep -Fqx 'version=v1.2.3' "$state/release-output" || die 'stable release version output mismatch'
sed -n '/^tags<<ARAIHU_TAGS$/,/^ARAIHU_TAGS$/p' "$state/release-output" |
	sed '1d;$d' > "$state/tags"
cat > "$state/expected-tags" <<'EOF'
ghcr.io/araihu/dex:v1.2.3
ghcr.io/araihu/dex:1.2
ghcr.io/araihu/dex:1
ghcr.io/araihu/dex:latest
EOF
cmp "$state/expected-tags" "$state/tags" || die 'stable release tag mapping mismatch'
if grep -Eiq ':(master|edge|pr[-0-9]*)$' "$state/tags"; then
	die 'mutable or pull-request tag emitted'
fi

for invalid in v1.2.3-rc.1 v1.2.3+build 1.2.3 v01.2.3 v1.02.3 v1.2.03 v1.2 v1.2.3.4; do
	if run_release_step tag "$invalid" "$state/rejected-output" >/dev/null 2>&1; then
		die "release metadata accepted malformed tag: $invalid"
	fi
done
if run_release_step branch v1.2.3 "$state/rejected-output" >/dev/null 2>&1; then
	die 'release metadata accepted a branch ref'
fi
if run_release_step tag v1.2.3 "$state/rejected-output" 0123456789abcdef0123456789abcdef01234567 >/dev/null 2>&1; then
	die 'release metadata accepted a tag not bound to the checked-out commit'
fi

make_oci() {
	output=$1
	mutation=$2
	python3 - "$repo" "$output" "$mutation" <<'PY'
import gzip
import hashlib
import io
import json
import pathlib
import tarfile
import sys

repo = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
mutation = sys.argv[3]

versions = {}
for line in (repo / 'versions.env').read_text().splitlines():
    key, value = line.split('=', 1)
    versions[key] = value

manifest_entries = []
for line in (repo / 'web/manifest.sha256').read_text().splitlines():
    digest, path = line.split('  ', 1)
    manifest_entries.append((digest, path))

blobs = {}

def canonical(value):
    return json.dumps(value, separators=(',', ':'), sort_keys=True).encode()

def add_blob(data):
    digest = hashlib.sha256(data).hexdigest()
    blobs[digest] = data
    return f'sha256:{digest}'

def descriptor(data, media_type, annotations=None, platform=None):
    digest = add_blob(data)
    result = {'mediaType': media_type, 'digest': digest, 'size': len(data)}
    if annotations:
        result['annotations'] = annotations
    if platform:
        result['platform'] = platform
    return result

def layer(architecture):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode='w') as archive:
        for expected_digest, path in manifest_entries:
            if path == 'static/theme-allowlist.txt':
                continue
            data = (repo / 'web' / path).read_bytes()
            if mutation == 'frontend' and architecture == 'arm64' and path == 'templates/header.html':
                data += b'\nmutation\n'
            info = tarfile.TarInfo(f'srv/dex/web/{path}')
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
    uncompressed = raw.getvalue()
    compressed = gzip.compress(uncompressed, mtime=0)
    return uncompressed, compressed

def image(architecture, os_name='linux'):
    raw_layer, compressed_layer = layer(architecture)
    labels = {
        'org.opencontainers.image.created': '2026-08-25T12:00:00Z',
        'org.opencontainers.image.revision': '0123456789abcdef0123456789abcdef01234567',
        'org.opencontainers.image.version': 'v1.2.3',
        'org.opencontainers.image.source': 'https://github.com/araihu/dex',
        'org.opencontainers.image.licenses': 'Apache-2.0 AND MIT',
        'io.araihu.dex.upstream.revision': versions['DEX_COMMIT'],
        'io.araihu.dex.upstream.digest': versions['DEX_IMAGE'].split('@', 1)[1],
        'io.araihu.dex.goshtoso.version': versions['GOSHTOSO_VERSION'],
        'io.araihu.dex.assets.version': versions['ARAIHU_ASSETS_VERSION'],
    }
    if mutation == 'label' and architecture == 'arm64':
        labels['io.araihu.dex.upstream.revision'] = '0' * 40
    config = canonical({
        'architecture': architecture,
        'os': os_name,
        'config': {'Labels': labels},
        'rootfs': {'type': 'layers', 'diff_ids': [f"sha256:{hashlib.sha256(raw_layer).hexdigest()}"]},
        'history': [],
    })
    config_descriptor = descriptor(config, 'application/vnd.oci.image.config.v1+json')
    layer_descriptor = descriptor(compressed_layer, 'application/vnd.oci.image.layer.v1.tar+gzip')
    manifest = canonical({
        'schemaVersion': 2,
        'mediaType': 'application/vnd.oci.image.manifest.v1+json',
        'config': config_descriptor,
        'layers': [layer_descriptor],
    })
    return descriptor(
        manifest,
        'application/vnd.oci.image.manifest.v1+json',
        platform={'os': os_name, 'architecture': architecture},
    )

def attestation(subject, omit_sbom=False):
    subject_digest = subject['digest']
    layers = []
    predicates = [
        ('https://slsa.dev/provenance/v1', {'buildType': 'https://mobyproject.org/buildkit@v1'}),
        ('https://spdx.dev/Document', {'SPDXID': 'SPDXRef-DOCUMENT', 'spdxVersion': 'SPDX-2.3'}),
    ]
    if omit_sbom:
        predicates.pop()
    for predicate_type, predicate in predicates:
        statement = canonical({
            '_type': 'https://in-toto.io/Statement/v1',
            'subject': [{'name': 'ghcr.io/araihu/dex', 'digest': {'sha256': subject_digest.removeprefix('sha256:')}}],
            'predicateType': predicate_type,
            'predicate': predicate,
        })
        layers.append(descriptor(
            statement,
            'application/vnd.in-toto+json',
            annotations={'in-toto.io/predicate-type': predicate_type},
        ))
    config = canonical({})
    manifest = canonical({
        'schemaVersion': 2,
        'mediaType': 'application/vnd.oci.image.manifest.v1+json',
        'config': descriptor(config, 'application/vnd.oci.empty.v1+json'),
        'layers': layers,
    })
    return descriptor(
        manifest,
        'application/vnd.oci.image.manifest.v1+json',
        annotations={
            'vnd.docker.reference.digest': subject_digest,
            'vnd.docker.reference.type': 'attestation-manifest',
        },
        platform={'os': 'unknown', 'architecture': 'unknown'},
    )

images = [image('amd64'), image('arm64')]
if mutation == 'platform':
    images.append(image('s390x'))
if mutation == 'foreign_os':
    images.append(image('amd64', 'windows'))
attestations = [
    attestation(subject, omit_sbom=(mutation == 'evidence' and subject['platform']['architecture'] == 'arm64'))
    for subject in images
]
release_index = canonical({
    'schemaVersion': 2,
    'mediaType': 'application/vnd.oci.image.index.v1+json',
    'manifests': images + attestations,
})
index = canonical({
    'schemaVersion': 2,
    'mediaType': 'application/vnd.oci.image.index.v1+json',
    'manifests': [descriptor(release_index, 'application/vnd.oci.image.index.v1+json')],
})

with tarfile.open(output, mode='w') as archive:
    files = {
        'oci-layout': canonical({'imageLayoutVersion': '1.0.0'}),
        'index.json': index,
    }
    files.update({f'blobs/sha256/{digest}': data for digest, data in blobs.items()})
    for name in sorted(files):
        data = files[name]
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o644
        info.mtime = 0
        archive.addfile(info, io.BytesIO(data))
PY
}

make_oci "$state/release.oci.tar" good
"$verifier" local "$state/release.oci.tar"
for mutation in platform foreign_os label frontend evidence; do
	make_oci "$state/$mutation.oci.tar" "$mutation"
	if "$verifier" local "$state/$mutation.oci.tar" >/dev/null 2>&1; then
		die "local verifier accepted $mutation mutation"
	fi
done

make_remote_index() {
	output=$1
	extra_os=$2
	python3 - "$output" "$extra_os" <<'PY'
import json
import pathlib
import sys

manifests = [
    {
        'mediaType': 'application/vnd.oci.image.manifest.v1+json',
        'digest': 'sha256:' + 'a' * 64,
        'size': 1,
        'platform': {'os': 'linux', 'architecture': 'amd64'},
    },
    {
        'mediaType': 'application/vnd.oci.image.manifest.v1+json',
        'digest': 'sha256:' + 'b' * 64,
        'size': 1,
        'platform': {'os': 'linux', 'architecture': 'arm64'},
    },
]
if sys.argv[2] == 'foreign_os':
    manifests.append({
        'mediaType': 'application/vnd.oci.image.manifest.v1+json',
        'digest': 'sha256:' + 'c' * 64,
        'size': 1,
        'platform': {'os': 'windows', 'architecture': 'amd64'},
    })
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    'schemaVersion': 2,
    'mediaType': 'application/vnd.oci.image.index.v1+json',
    'manifests': manifests,
}, separators=(',', ':'), sort_keys=True))
PY
}

mkdir -p "$state/remote-bin"
cat > "$state/remote-bin/docker" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
	*' --raw '*) cat "$REMOTE_INDEX" ;;
	*'.SBOM'*) printf '%s\n' '{"SPDX":{"SPDXID":"SPDXRef-DOCUMENT"}}' ;;
	*'.Provenance'*) printf '%s\n' '{"SLSA":{"buildType":"https://mobyproject.org/buildkit@v1"}}' ;;
	*'.Image'*)
		jq -cn \
			--arg revision "$REMOTE_REVISION" \
			--arg upstream_revision "$REMOTE_UPSTREAM_REVISION" \
			--arg upstream_digest "$REMOTE_UPSTREAM_DIGEST" \
			--arg goshtoso "$REMOTE_GOSHTOSO_VERSION" \
			--arg assets "$REMOTE_ASSETS_VERSION" \
			'{config:{Labels:{
				"org.opencontainers.image.created":"2026-08-25T12:00:00Z",
				"org.opencontainers.image.revision":$revision,
				"org.opencontainers.image.version":"v1.2.3",
				"org.opencontainers.image.source":"https://github.com/araihu/dex",
				"org.opencontainers.image.licenses":"Apache-2.0 AND MIT",
				"io.araihu.dex.upstream.revision":$upstream_revision,
				"io.araihu.dex.upstream.digest":$upstream_digest,
				"io.araihu.dex.goshtoso.version":$goshtoso,
				"io.araihu.dex.assets.version":$assets
			}}}'
		;;
	*) exit 1 ;;
esac
EOF
cat > "$state/remote-bin/cosign" <<'EOF'
#!/bin/sh
set -eu
identity=https://github.com/araihu/dex/.github/workflows/release.yml@refs/tags/v1.2.3
case "$*" in
	*"--certificate-identity $identity"*'--certificate-oidc-issuer https://token.actions.githubusercontent.com'*) ;;
	*) exit 1 ;;
esac
EOF
cat > "$state/remote-bin/gh" <<'EOF'
#!/bin/sh
set -eu
identity=https://github.com/araihu/dex/.github/workflows/release.yml@refs/tags/v1.2.3
case "$*" in
	*'attestation verify oci://ghcr.io/araihu/dex@sha256:'*'--repo araihu/dex'*"--cert-identity $identity"*'--source-ref refs/tags/v1.2.3'*"--source-digest $REMOTE_REVISION"*'--predicate-type https://slsa.dev/provenance/v1'*) ;;
	*) exit 1 ;;
esac
EOF
chmod +x "$state/remote-bin/docker" "$state/remote-bin/cosign" "$state/remote-bin/gh"

remote_revision=0123456789abcdef0123456789abcdef01234567
remote_upstream_revision=$(sed -n 's/^DEX_COMMIT=//p' "$repo/versions.env")
remote_upstream_digest=$(sed -n 's/^DEX_IMAGE=.*@//p' "$repo/versions.env")
remote_goshtoso_version=$(sed -n 's/^GOSHTOSO_VERSION=//p' "$repo/versions.env")
remote_assets_version=$(sed -n 's/^ARAIHU_ASSETS_VERSION=//p' "$repo/versions.env")

run_remote_fixture() {
	index=$1
	REMOTE_INDEX=$index \
		REMOTE_REVISION=$remote_revision \
		REMOTE_UPSTREAM_REVISION=$remote_upstream_revision \
		REMOTE_UPSTREAM_DIGEST=$remote_upstream_digest \
		REMOTE_GOSHTOSO_VERSION=$remote_goshtoso_version \
		REMOTE_ASSETS_VERSION=$remote_assets_version \
		PATH="$state/remote-bin:$PATH" \
		"$verifier" remote ghcr.io/araihu/dex:v1.2.3
}

make_remote_index "$state/remote-index.json" good
run_remote_fixture "$state/remote-index.json" >/dev/null
make_remote_index "$state/remote-foreign-os-index.json" foreign_os
if run_remote_fixture "$state/remote-foreign-os-index.json" >/dev/null 2>&1; then
	die 'remote verifier accepted a foreign platform mutation'
fi

printf '%s\n' 'release policy: ok'
