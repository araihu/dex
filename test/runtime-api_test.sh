#!/bin/sh
set -eu

image=${1:?usage: runtime-api_test.sh IMAGE}
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$repo/versions.env"
upstream_version=${DEX_IMAGE#*:}
upstream_version=${upstream_version%@*}
expected_version=$upstream_version+araihu.password-profile.v1

container=araihu-dex-api-test-$$
cleanup() {
	docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

docker run -d --name "$container" -p 127.0.0.1::5557 \
	--mount "type=bind,src=$repo/test/fixtures/dex-api.yaml,dst=/etc/dex/api-test.yaml,readonly" \
	"$image" dex serve /etc/dex/api-test.yaml >/dev/null
address=$(docker port "$container" 5557/tcp)
address=127.0.0.1:${address##*:}

(
	cd "$repo/api/v2"
	GOWORK=off go run ../../test/runtime-api-client.go "$address" "$expected_version"
)
