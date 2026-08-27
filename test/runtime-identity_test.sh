#!/bin/sh
set -eu

image=${1:?usage: runtime-identity_test.sh IMAGE}
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$repo/versions.env"

upstream_version=${DEX_IMAGE#*:}
upstream_version=${upstream_version%@*}
expected_version=$upstream_version+araihu.password-profile.v1

image_version() {
	docker run --rm --entrypoint /usr/local/bin/dex "$1" version |
		sed -n 's/^Dex Version: //p'
}

actual_version=$(image_version "$image")
[ "$actual_version" = "$expected_version" ] || {
	printf '%s\n' "runtime-identity: derived version $actual_version, want $expected_version" >&2
	exit 1
}

official_version=$(image_version "$DEX_IMAGE")
[ "$official_version" = "$upstream_version" ] || {
	printf '%s\n' "runtime-identity: official version $official_version, want $upstream_version" >&2
	exit 1
}
[ "$official_version" != "$actual_version" ] || {
	printf '%s\n' 'runtime-identity: derived image is indistinguishable from official Dex' >&2
	exit 1
}
