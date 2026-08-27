#!/bin/sh
set -eu

die() {
	printf '%s\n' "prepare-dex-source: $*" >&2
	exit 1
}

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
source_dir=${1:?usage: prepare-dex-source.sh SOURCE_DIR}

[ -f "$source_dir/api/v2/api.proto" ] || die "Dex api/v2 source not found: $source_dir"
[ -f "$source_dir/server/apiserver/passwords.go" ] || die "Dex password API source not found: $source_dir"

hash_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		die 'sha256 tool is required'
	fi
}

verify_preimage() {
	want=$1
	path=$2
	got=$(hash_file "$source_dir/$path")
	[ "$got" = "$want" ] || die "upstream preimage changed: $path"
}

verify_preimage 9b0f8d72b1a7dd14652529dee108bc3c861782d485b17a2a13558b9db1d40b28 api/v2/api.proto
verify_preimage 5a45c246943922682f65ed37346454cbb9f40a82a2b030beb4b7858ff6df9a7b api/v2/api.pb.go
verify_preimage abfa4e71cb3117c93fe3276dab3267d9794b7b55cd5d4ff9dbde4acf0eb2806a api/v2/api_grpc.pb.go
verify_preimage 1a82587b962fe689a8d91f85ddace36642bbcbf4d2c05c57f2ff8600f25f6640 api/v2/go.mod
verify_preimage 3f6af5eb98fab9eb7f19ff05b48eb51bb323ec6ed551f7bca408134f8b7fd77b api/v2/go.sum
verify_preimage 7234b495ee782d25d36b7ddb61cd346285871dd46c678b86ef3cfdf45b83f0c2 server/apiserver/passwords.go

for file in api.proto api.pb.go api_grpc.pb.go go.mod go.sum password_compatibility_test.go; do
	cp "$repo/api/v2/$file" "$source_dir/api/v2/$file"
done
cp "$repo/dex/server/apiserver/passwords.go" "$source_dir/server/apiserver/passwords.go"
