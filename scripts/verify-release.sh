#!/usr/bin/env bash
set -euo pipefail

die() {
	printf '%s\n' "verify-release: $*" >&2
	exit 1
}

usage() {
	die 'usage: scripts/verify-release.sh local <oci.tar> | remote <image-ref>'
}

[[ $# -eq 2 ]] || usage
mode=$1
subject=$2
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
versions=$repo/versions.env
frontend_manifest=$repo/web/manifest.sha256

[[ -f "$versions" ]] || die "versions file not found: $versions"
[[ -f "$frontend_manifest" ]] || die "frontend manifest not found: $frontend_manifest"

version_value() {
	local key=$1
	local count value
	count=$(awk -F= -v key="$key" '$1 == key { count++ } END { print count + 0 }' "$versions")
	[[ "$count" -eq 1 ]] || die "expected one $key entry in versions.env"
	value=$(awk -v prefix="$key=" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' "$versions")
	[[ -n "$value" ]] || die "empty $key entry in versions.env"
	printf '%s\n' "$value"
}

dex_commit=$(version_value DEX_COMMIT)
dex_image=$(version_value DEX_IMAGE)
goshtoso_version=$(version_value GOSHTOSO_VERSION)
assets_version=$(version_value ARAIHU_ASSETS_VERSION)
upstream_digest=${dex_image##*@}

case "$mode" in
	local)
		[[ -f "$subject" ]] || die "OCI archive not found: $subject"
		command -v python3 >/dev/null 2>&1 || die 'python3 is required for local verification'
		DEX_COMMIT=$dex_commit \
		UPSTREAM_DIGEST=$upstream_digest \
		GOSHTOSO_VERSION=$goshtoso_version \
		ASSETS_VERSION=$assets_version \
		python3 - "$subject" "$frontend_manifest" <<'PY'
import datetime
import hashlib
import io
import json
import os
import pathlib
import re
import sys
import tarfile


def fail(message):
    raise SystemExit(f'verify-release: {message}')


archive_path = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])

try:
    archive = tarfile.open(archive_path, mode='r:*')
except (OSError, tarfile.TarError) as error:
    fail(f'cannot read OCI archive: {error}')

members = {}
with archive:
    for member in archive.getmembers():
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts:
            fail(f'unsafe OCI archive path: {member.name}')
        normalized = path.as_posix().removeprefix('./')
        if not normalized or normalized in members:
            fail(f'duplicate or empty OCI archive path: {member.name}')
        if member.isdir():
            continue
        if not member.isfile():
            fail(f'unsupported OCI archive entry: {member.name}')
        extracted = archive.extractfile(member)
        if extracted is None:
            fail(f'cannot read OCI archive entry: {member.name}')
        members[normalized] = extracted.read()


def read_json(data, description):
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f'invalid {description} JSON: {error}')
    if not isinstance(value, dict):
        fail(f'{description} must be a JSON object')
    return value


layout = read_json(members.get('oci-layout', b''), 'OCI layout')
if layout.get('imageLayoutVersion') != '1.0.0':
    fail('unsupported OCI layout version')
index = read_json(members.get('index.json', b''), 'OCI index')
if index.get('mediaType') != 'application/vnd.oci.image.index.v1+json':
    fail('root object is not an OCI image index')
root_descriptors = index.get('manifests')
if not isinstance(root_descriptors, list):
    fail('OCI index manifests missing')

digest_pattern = re.compile(r'^sha256:([0-9a-f]{64})$')


def blob(descriptor, description):
    if not isinstance(descriptor, dict):
        fail(f'{description} descriptor must be an object')
    digest = descriptor.get('digest', '')
    match = digest_pattern.fullmatch(digest)
    if not match:
        fail(f'{description} has an invalid digest')
    data = members.get(f'blobs/sha256/{match.group(1)}')
    if data is None:
        fail(f'{description} blob is missing')
    if len(data) != descriptor.get('size'):
        fail(f'{description} size mismatch')
    if hashlib.sha256(data).hexdigest() != match.group(1):
        fail(f'{description} digest mismatch')
    return data


def flatten_descriptors(candidates, seen_indexes=None):
    if seen_indexes is None:
        seen_indexes = set()
    flattened = []
    for descriptor in candidates:
        if not isinstance(descriptor, dict):
            fail('OCI index descriptor must be an object')
        if descriptor.get('mediaType') != 'application/vnd.oci.image.index.v1+json':
            flattened.append(descriptor)
            continue
        digest = descriptor.get('digest')
        if digest in seen_indexes:
            fail('cyclic OCI image index')
        seen_indexes.add(digest)
        nested = read_json(blob(descriptor, 'nested OCI index'), 'nested OCI index')
        if nested.get('mediaType') != 'application/vnd.oci.image.index.v1+json':
            fail('nested object is not an OCI image index')
        manifests = nested.get('manifests')
        if not isinstance(manifests, list):
            fail('nested OCI index manifests missing')
        flattened.extend(flatten_descriptors(manifests, seen_indexes))
    return flattened


descriptors = flatten_descriptors(root_descriptors)
platform_images = {}
for descriptor in descriptors:
    if not isinstance(descriptor, dict):
        fail('OCI index descriptor must be an object')
    annotations = descriptor.get('annotations') or {}
    if annotations.get('vnd.docker.reference.type') == 'attestation-manifest':
        continue
    if descriptor.get('mediaType') != 'application/vnd.oci.image.manifest.v1+json':
        fail('OCI index contains an unsupported non-attestation descriptor')
    platform = descriptor.get('platform') or {}
    os_name = platform.get('os')
    architecture = platform.get('architecture')
    platform_key = (os_name, architecture)
    if platform_key in platform_images:
        fail(f'duplicate {os_name}/{architecture} manifest')
    platform_images[platform_key] = descriptor

expected_platforms = {('linux', 'amd64'), ('linux', 'arm64')}
if set(platform_images) != expected_platforms:
    rendered = sorted(f'{os_name}/{architecture}' for os_name, architecture in platform_images)
    fail(f'platforms must be exactly linux/amd64 and linux/arm64, got {rendered}')
images = {architecture: platform_images[('linux', architecture)] for architecture in ('amd64', 'arm64')}

required_labels = {
    'org.opencontainers.image.source': 'https://github.com/araihu/dex',
    'org.opencontainers.image.licenses': 'Apache-2.0 AND MIT AND OFL-1.1 AND BSD-3-Clause',
    'io.araihu.dex.upstream.revision': os.environ['DEX_COMMIT'],
    'io.araihu.dex.upstream.digest': os.environ['UPSTREAM_DIGEST'],
    'io.araihu.dex.goshtoso.version': os.environ['GOSHTOSO_VERSION'],
    'io.araihu.dex.assets.version': os.environ['ASSETS_VERSION'],
}
revision_pattern = re.compile(r'^[0-9a-f]{40}$')
version_pattern = re.compile(r'^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')


def validate_created(value):
    if not isinstance(value, str) or not value.endswith('Z'):
        fail('creation label must be an RFC3339 UTC timestamp')
    try:
        datetime.datetime.fromisoformat(value[:-1] + '+00:00')
    except ValueError:
        fail('creation label must be an RFC3339 UTC timestamp')


def expected_files():
    expected = {}
    for number, line in enumerate(manifest_path.read_text().splitlines(), start=1):
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match:
            fail(f'invalid frontend manifest line {number}')
        digest, relative = match.groups()
        path = pathlib.PurePosixPath(relative)
        if path.is_absolute() or '..' in path.parts or relative in expected:
            fail(f'unsafe or duplicate frontend manifest path: {relative}')
        if relative == 'static/theme-allowlist.txt':
            continue
        expected[relative] = digest
    if not expected:
        fail('frontend manifest is empty')
    return expected


frontend_expected = expected_files()


def layer_frontend_files(layer_descriptor, current):
    data = blob(layer_descriptor, 'image layer')
    try:
        layer = tarfile.open(fileobj=io.BytesIO(data), mode='r:*')
    except tarfile.TarError as error:
        fail(f'cannot read image layer: {error}')
    with layer:
        for member in layer.getmembers():
            path = pathlib.PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts:
                fail(f'unsafe image layer path: {member.name}')
            normalized = path.as_posix().removeprefix('./')
            basename = pathlib.PurePosixPath(normalized).name
            parent = pathlib.PurePosixPath(normalized).parent.as_posix()
            if basename == '.wh..wh..opq':
                prefix = parent.rstrip('/') + '/'
                for existing in list(current):
                    if existing.startswith(prefix):
                        current.pop(existing)
                continue
            if basename.startswith('.wh.'):
                removed = pathlib.PurePosixPath(parent, basename[4:]).as_posix()
                current.pop(removed, None)
                prefix = removed.rstrip('/') + '/'
                for existing in list(current):
                    if existing.startswith(prefix):
                        current.pop(existing)
                continue
            if normalized not in frontend_targets:
                continue
            if not member.isfile():
                fail(f'frontend path is not a regular file: {normalized}')
            extracted = layer.extractfile(member)
            if extracted is None:
                fail(f'cannot read frontend path: {normalized}')
            current[normalized] = extracted.read()


frontend_targets = {f'srv/dex/web/{path}' for path in frontend_expected}
platform_frontend = {}
common_label_values = None
for architecture in ('amd64', 'arm64'):
    descriptor = images[architecture]
    manifest = read_json(blob(descriptor, f'linux/{architecture} manifest'), f'linux/{architecture} manifest')
    if manifest.get('mediaType') != 'application/vnd.oci.image.manifest.v1+json':
        fail(f'linux/{architecture} descriptor is not an OCI image manifest')
    config = read_json(blob(manifest.get('config'), f'linux/{architecture} config'), f'linux/{architecture} config')
    labels = (config.get('config') or {}).get('Labels')
    if not isinstance(labels, dict):
        fail(f'linux/{architecture} labels missing')
    for key, expected in required_labels.items():
        if labels.get(key) != expected:
            fail(f'linux/{architecture} label mismatch: {key}')
    revision = labels.get('org.opencontainers.image.revision', '')
    version = labels.get('org.opencontainers.image.version', '')
    created = labels.get('org.opencontainers.image.created', '')
    if not revision_pattern.fullmatch(revision):
        fail(f'linux/{architecture} AraiHu revision label is invalid')
    if not version_pattern.fullmatch(version):
        fail(f'linux/{architecture} AraiHu version label is not stable vX.Y.Z')
    validate_created(created)
    label_values = {**required_labels, 'revision': revision, 'version': version, 'created': created}
    if common_label_values is None:
        common_label_values = label_values
    elif common_label_values != label_values:
        fail('per-platform release labels differ')

    layers = manifest.get('layers')
    if not isinstance(layers, list):
        fail(f'linux/{architecture} layers missing')
    current = {}
    for layer_descriptor in layers:
        layer_frontend_files(layer_descriptor, current)
    files = {}
    for relative, expected_digest in frontend_expected.items():
        target = f'srv/dex/web/{relative}'
        data = current.get(target)
        if data is None:
            fail(f'linux/{architecture} frontend file missing: {relative}')
        if hashlib.sha256(data).hexdigest() != expected_digest:
            fail(f'linux/{architecture} frontend checksum mismatch: {relative}')
        files[relative] = data
    platform_frontend[architecture] = files

if platform_frontend['amd64'] != platform_frontend['arm64']:
    fail('frontend bytes differ between linux/amd64 and linux/arm64')

attestations = {}
known_image_digests = {descriptor.get('digest') for descriptor in images.values()}
for descriptor in descriptors:
    annotations = descriptor.get('annotations') or {}
    if annotations.get('vnd.docker.reference.type') != 'attestation-manifest':
        continue
    referenced = annotations.get('vnd.docker.reference.digest')
    if not digest_pattern.fullmatch(referenced or ''):
        fail('attestation manifest has invalid subject digest')
    if referenced not in known_image_digests:
        fail('attestation manifest references an unknown platform image')
    attestation = read_json(blob(descriptor, 'attestation manifest'), 'attestation manifest')
    if attestation.get('mediaType') != 'application/vnd.oci.image.manifest.v1+json':
        fail('attestation manifest has an invalid media type')
    layers = attestation.get('layers')
    if not isinstance(layers, list):
        fail('attestation layers missing')
    if len(layers) != 2:
        fail('attestation must contain exactly one SBOM and one provenance statement')
    predicates = attestations.setdefault(referenced, set())
    for layer_descriptor in layers:
        if not isinstance(layer_descriptor, dict):
            fail('attestation layer descriptor must be an object')
        predicate_type = (layer_descriptor.get('annotations') or {}).get('in-toto.io/predicate-type')
        if predicate_type not in {'https://spdx.dev/Document', 'https://slsa.dev/provenance/v1'}:
            fail('attestation predicate type is not an allowed SBOM or provenance type')
        statement = read_json(blob(layer_descriptor, 'attestation statement'), 'attestation statement')
        if statement.get('_type') not in {'https://in-toto.io/Statement/v0.1', 'https://in-toto.io/Statement/v1'}:
            fail('attestation statement is not an allowed in-toto statement')
        if statement.get('predicateType') != predicate_type:
            fail('attestation predicate annotation mismatch')
        subjects = statement.get('subject')
        if not isinstance(subjects, list) or len(subjects) > 1:
            fail('attestation statement must contain zero or one subject')
        if subjects:
            attestation_subject = subjects[0]
            if not isinstance(attestation_subject, dict) or attestation_subject.get('name') != 'ghcr.io/araihu/dex':
                fail('attestation subject name mismatch')
            subject_digest = attestation_subject.get('digest')
            if not isinstance(subject_digest, dict) or set(subject_digest) != {'sha256'}:
                fail('attestation subject digest must be a sha256 digest')
            if 'sha256:' + str(subject_digest['sha256']) != referenced:
                fail('attestation subject digest does not match the referenced image')
        predicate = statement.get('predicate')
        if not isinstance(predicate, dict) or not predicate:
            fail('attestation predicate body must be an object')
        if predicate_type == 'https://spdx.dev/Document':
            if predicate.get('SPDXID') != 'SPDXRef-DOCUMENT' or not str(predicate.get('spdxVersion', '')).startswith('SPDX-'):
                fail('SPDX attestation predicate body is invalid')
        else:
            build_definition = predicate.get('buildDefinition')
            run_details = predicate.get('runDetails')
            if not isinstance(build_definition, dict) or not build_definition or build_definition.get('buildType') not in {
                'https://mobyproject.org/buildkit@v1',
                'https://github.com/moby/buildkit/blob/master/docs/attestations/slsa-definitions.md',
            }:
                fail('SLSA provenance build definition is not BuildKit')
            if not isinstance(run_details, dict) or not run_details:
                fail('SLSA provenance run details are missing')
        predicates.add(predicate_type)

for architecture, descriptor in images.items():
    predicates = attestations.get(descriptor.get('digest'), set())
    if 'https://spdx.dev/Document' not in predicates:
        fail(f'linux/{architecture} SPDX SBOM attestation missing')
    if not any(value and value.startswith('https://slsa.dev/provenance/') for value in predicates):
        fail(f'linux/{architecture} provenance attestation missing')

print('verify-release: local ok')
PY
		;;
	remote)
		command -v docker >/dev/null 2>&1 || die 'docker with Buildx is required for remote verification'
		command -v jq >/dev/null 2>&1 || die 'jq is required for remote verification'
		command -v python3 >/dev/null 2>&1 || die 'python3 is required for remote verification'
		command -v cosign >/dev/null 2>&1 || die 'cosign is required for remote verification'
		command -v gh >/dev/null 2>&1 || die 'GitHub CLI is required for remote verification'
		[[ "$subject" =~ ^ghcr\.io/araihu/dex(@sha256:[0-9a-f]{64}|:[A-Za-z0-9._-]+)$ ]] ||
			die 'remote image must be an exact ghcr.io/araihu/dex tag or digest reference'

		state=$(mktemp -d "${TMPDIR:-/tmp}/araihu-dex-release-verify.XXXXXX")
		cleanup() {
			rm -rf "$state"
		}
		trap cleanup EXIT HUP INT TERM

		image=ghcr.io/araihu/dex
		docker buildx imagetools inspect --raw "$subject" > "$state/index.json"
		digest=$(python3 - "$state/index.json" <<'PY'
import hashlib
import pathlib
import sys
print('sha256:' + hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)
		[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die 'published subject digest is invalid'

		jq -e '
			[.manifests[] | select((.annotations["vnd.docker.reference.type"] // "") != "attestation-manifest")] as $images |
			($images | length == 2) and
			([$images[] | select(.mediaType == "application/vnd.oci.image.manifest.v1+json")] | length == 2) and
			([$images[] | [.platform.os, .platform.architecture]] | sort == [["linux", "amd64"], ["linux", "arm64"]])
		' "$state/index.json" >/dev/null || die 'published platforms must be exactly linux/amd64 and linux/arm64'

		jq -r '.manifests[] | select(.platform.os == "linux" and .platform.architecture != "unknown") | [.platform.architecture, .digest] | @tsv' \
			"$state/index.json" > "$state/platforms"
		while IFS=$'\t' read -r architecture platform_digest; do
			docker buildx imagetools inspect "$image@$platform_digest" --format '{{ json .Image }}' > "$state/$architecture-image.json"
		done < "$state/platforms"

		for architecture in amd64 arm64; do
			labels=$state/$architecture-image.json
			[[ -s "$labels" ]] || die "linux/$architecture image config missing"
			[[ $(jq -r '.config.Labels["org.opencontainers.image.source"] // empty' "$labels") == https://github.com/araihu/dex ]] ||
				die "linux/$architecture source label mismatch"
			[[ $(jq -r '.config.Labels["org.opencontainers.image.licenses"] // empty' "$labels") == 'Apache-2.0 AND MIT AND OFL-1.1 AND BSD-3-Clause' ]] ||
				die "linux/$architecture license label mismatch"
			[[ $(jq -r '.config.Labels["io.araihu.dex.upstream.revision"] // empty' "$labels") == "$dex_commit" ]] ||
				die "linux/$architecture upstream revision label mismatch"
			[[ $(jq -r '.config.Labels["io.araihu.dex.upstream.digest"] // empty' "$labels") == "$upstream_digest" ]] ||
				die "linux/$architecture upstream digest label mismatch"
			[[ $(jq -r '.config.Labels["io.araihu.dex.goshtoso.version"] // empty' "$labels") == "$goshtoso_version" ]] ||
				die "linux/$architecture Goshtoso label mismatch"
			[[ $(jq -r '.config.Labels["io.araihu.dex.assets.version"] // empty' "$labels") == "$assets_version" ]] ||
				die "linux/$architecture Assets label mismatch"
		done

		revision=$(jq -r '.config.Labels["org.opencontainers.image.revision"] // empty' "$state/amd64-image.json")
		version=$(jq -r '.config.Labels["org.opencontainers.image.version"] // empty' "$state/amd64-image.json")
		created=$(jq -r '.config.Labels["org.opencontainers.image.created"] // empty' "$state/amd64-image.json")
		[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || die 'published AraiHu revision label is invalid'
		[[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die 'published version is not stable vX.Y.Z'
		major=${BASH_REMATCH[1]}
		minor=${BASH_REMATCH[2]}
		python3 - "$created" <<'PY'
import datetime
import sys
value = sys.argv[1]
if not value.endswith('Z'):
    raise SystemExit('verify-release: published creation label is not RFC3339 UTC')
try:
    datetime.datetime.fromisoformat(value[:-1] + '+00:00')
except ValueError:
    raise SystemExit('verify-release: published creation label is not RFC3339 UTC')
PY

		for architecture in amd64 arm64; do
			labels=$state/$architecture-image.json
			[[ $(jq -r '.config.Labels["org.opencontainers.image.revision"] // empty' "$labels") == "$revision" ]] ||
				die 'per-platform revision labels differ'
			[[ $(jq -r '.config.Labels["org.opencontainers.image.version"] // empty' "$labels") == "$version" ]] ||
				die 'per-platform version labels differ'
			[[ $(jq -r '.config.Labels["org.opencontainers.image.created"] // empty' "$labels") == "$created" ]] ||
				die 'per-platform creation labels differ'
		done

	expected_refs=(
			"$image:$version"
			"$image:$major.$minor"
			"$image:$major"
			"$image:latest"
		)
		candidate_subject=false
		if [[ "$subject" =~ ^$image:candidate-[0-9a-f]{40}$ ]]; then
			candidate_subject=true
		elif [[ "$subject" != "$image@$digest" ]]; then
			matched=false
			for expected_ref in "${expected_refs[@]}"; do
				[[ "$subject" != "$expected_ref" ]] || matched=true
			done
			[[ "$matched" == true ]] || die 'input tag is not one of the four stable release tags'
		fi

		if [[ "$candidate_subject" == false ]]; then
			for expected_ref in "${expected_refs[@]}"; do
				docker buildx imagetools inspect --raw "$expected_ref" > "$state/tag-index.json"
				tag_digest=$(python3 - "$state/tag-index.json" <<'PY'
import hashlib
import pathlib
import sys
print('sha256:' + hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)
				[[ "$tag_digest" == "$digest" ]] || die "tag does not resolve to published subject: $expected_ref"
			done
		fi

		docker buildx imagetools inspect "$image@$digest" --format '{{ json .SBOM }}' > "$state/sbom.json"
		jq -e '.. | objects | select(.SPDXID? == "SPDXRef-DOCUMENT")' "$state/sbom.json" >/dev/null ||
			die 'published SPDX JSON SBOM missing'
		docker buildx imagetools inspect "$image@$digest" --format '{{ json .Provenance }}' > "$state/provenance.json"
		jq -e '.. | objects | select(.buildType? == "https://mobyproject.org/buildkit@v1")' "$state/provenance.json" >/dev/null ||
			die 'published BuildKit provenance missing'

		identity="https://github.com/araihu/dex/.github/workflows/release.yml@refs/tags/$version"
		cosign verify "$image@$digest" \
			--certificate-identity "$identity" \
			--certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null
		gh attestation verify "oci://$image@$digest" \
			--repo araihu/dex \
			--cert-identity "$identity" \
			--source-ref "refs/tags/$version" \
			--source-digest "$revision" \
			--predicate-type https://slsa.dev/provenance/v1 >/dev/null

		printf '%s\n' "verify-release: remote ok: $image@$digest"
		;;
	*)
		usage
		;;
esac
