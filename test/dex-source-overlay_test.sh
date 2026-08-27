#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/araihu-dex-source-overlay.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

tar -xzf "$repo/.cache/sources/downloads/dex.tar.gz" -C "$tmp"
source_dir=$tmp/dex-$(sed -n 's/^DEX_COMMIT=//p' "$repo/versions.env")

drift_dir=$tmp/dex-drift
mkdir -p "$drift_dir/api/v2" "$drift_dir/server/apiserver"
cp "$source_dir"/api/v2/api.proto "$source_dir"/api/v2/api.pb.go \
	"$source_dir"/api/v2/api_grpc.pb.go "$source_dir"/api/v2/go.mod \
	"$source_dir"/api/v2/go.sum "$drift_dir/api/v2/"
cp "$source_dir/server/apiserver/passwords.go" "$drift_dir/server/apiserver/"
printf '\n// simulated upstream drift\n' >>"$drift_dir/api/v2/api.proto"
if "$repo/scripts/prepare-dex-source.sh" "$drift_dir" >"$tmp/drift.log" 2>&1; then
	printf '%s\n' 'source overlay accepted an unknown upstream preimage' >&2
	exit 1
fi
grep -q 'upstream preimage changed: api/v2/api.proto' "$tmp/drift.log"

"$repo/scripts/prepare-dex-source.sh" "$source_dir"
cp "$repo/dex/server/apiserver/password_profile_test.go" "$source_dir/server/apiserver/"

(
	cd "$source_dir/api/v2"
	GOWORK=off go test ./...
)
(
	cd "$source_dir"
	GOWORK=off go test ./server/apiserver ./server
)
