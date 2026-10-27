#!/bin/sh
set -eu

die() {
	printf '%s\n' "fetch-sources: $*" >&2
	exit 1
}

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
lock_file=${VERSIONS_FILE:-${FETCH_VERSIONS:-$repo/versions.env}}
[ -f "$lock_file" ] || die "lock file not found: $lock_file"

DEX_COMMIT=
DEX_IMAGE=
DEX_SERVER_VERSION=
DEX_SOURCE_URL=
DEX_SOURCE_FILENAME=
DEX_SOURCE_SHA256=
DEX_BASE_X_MOD_VERSION=
DEX_X_MOD_VERSION=
DEX_BASE_API_GRPC_VERSION=
DEX_API_GRPC_VERSION=
GOSHTOSO_MODULE=
GOSHTOSO_VERSION=
GOSHTOSO_MODULE_SUM=
GOSHTOSO_GOMOD_SUM=
GOSHTOSO_THEME_SHA256=
GOSHTOSO_CATALOG_SHA256=
ARAIHU_ASSETS_VERSION=
ASSETS_ARCHIVE_URL=
ASSETS_ARCHIVE_FILENAME=
ASSETS_ARCHIVE_SHA256=
ASSETS_RELEASE_SUMS_URL=
ASSETS_RELEASE_SUMS_FILENAME=
ASSETS_RELEASE_SUMS_SHA256=
ASSETS_MEMBER_MANIFEST_URL=
ASSETS_MEMBER_MANIFEST_FILENAME=
ASSETS_MEMBER_MANIFEST_SHA256=
ASSET_MEMBER_COUNT=
ASSET_MEMBER_1=
ASSET_MEMBER_1_SHA256=
ASSET_MEMBER_2=
ASSET_MEMBER_2_SHA256=
ASSET_MEMBER_3=
ASSET_MEMBER_3_SHA256=
ASSET_MEMBER_4=
ASSET_MEMBER_4_SHA256=
ASSET_MEMBER_5=
ASSET_MEMBER_5_SHA256=
ASSET_MEMBER_6=
ASSET_MEMBER_6_SHA256=
ASSET_MEMBER_7=
ASSET_MEMBER_7_SHA256=
ASSET_MEMBER_8=
ASSET_MEMBER_8_SHA256=
TAILWIND_VERSION=
TAILWIND_PACKAGE_INTEGRITY=
TAILWIND_CLI_PACKAGE_INTEGRITY=
NODE_VERSION=
NPM_VERSION=
PLAYWRIGHT_VERSION=
AXE_PLAYWRIGHT_VERSION=
ACTIONLINT_VERSION=

seen_keys=
while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in
		''|'#'*) continue ;;
		*=*)
			key=${line%%=*}
			value=${line#*=}
			;;
		*) die "invalid lock line" ;;
	esac
	case "$key" in
		''|*[!A-Z0-9_]*) die "invalid lock key: $key" ;;
	esac
	case " $seen_keys " in
		*" $key "*) die "duplicate lock key: $key" ;;
	esac
	seen_keys="$seen_keys$key "
	case "$key" in
		DEX_COMMIT) DEX_COMMIT=$value ;;
		DEX_IMAGE) DEX_IMAGE=$value ;;
		DEX_SERVER_VERSION) DEX_SERVER_VERSION=$value ;;
		DEX_SOURCE_URL) DEX_SOURCE_URL=$value ;;
		DEX_SOURCE_FILENAME) DEX_SOURCE_FILENAME=$value ;;
		DEX_SOURCE_SHA256) DEX_SOURCE_SHA256=$value ;;
		DEX_BASE_X_MOD_VERSION) DEX_BASE_X_MOD_VERSION=$value ;;
		DEX_X_MOD_VERSION) DEX_X_MOD_VERSION=$value ;;
		DEX_BASE_API_GRPC_VERSION) DEX_BASE_API_GRPC_VERSION=$value ;;
		DEX_API_GRPC_VERSION) DEX_API_GRPC_VERSION=$value ;;
		GOSHTOSO_MODULE) GOSHTOSO_MODULE=$value ;;
		GOSHTOSO_VERSION) GOSHTOSO_VERSION=$value ;;
		GOSHTOSO_MODULE_SUM) GOSHTOSO_MODULE_SUM=$value ;;
		GOSHTOSO_GOMOD_SUM) GOSHTOSO_GOMOD_SUM=$value ;;
		GOSHTOSO_THEME_SHA256) GOSHTOSO_THEME_SHA256=$value ;;
		GOSHTOSO_CATALOG_SHA256) GOSHTOSO_CATALOG_SHA256=$value ;;
		ARAIHU_ASSETS_VERSION) ARAIHU_ASSETS_VERSION=$value ;;
		ASSETS_ARCHIVE_URL) ASSETS_ARCHIVE_URL=$value ;;
		ASSETS_ARCHIVE_FILENAME) ASSETS_ARCHIVE_FILENAME=$value ;;
		ASSETS_ARCHIVE_SHA256) ASSETS_ARCHIVE_SHA256=$value ;;
		ASSETS_RELEASE_SUMS_URL) ASSETS_RELEASE_SUMS_URL=$value ;;
		ASSETS_RELEASE_SUMS_FILENAME) ASSETS_RELEASE_SUMS_FILENAME=$value ;;
		ASSETS_RELEASE_SUMS_SHA256) ASSETS_RELEASE_SUMS_SHA256=$value ;;
		ASSETS_MEMBER_MANIFEST_URL) ASSETS_MEMBER_MANIFEST_URL=$value ;;
		ASSETS_MEMBER_MANIFEST_FILENAME) ASSETS_MEMBER_MANIFEST_FILENAME=$value ;;
		ASSETS_MEMBER_MANIFEST_SHA256) ASSETS_MEMBER_MANIFEST_SHA256=$value ;;
		ASSET_MEMBER_COUNT) ASSET_MEMBER_COUNT=$value ;;
		ASSET_MEMBER_1) ASSET_MEMBER_1=$value ;;
		ASSET_MEMBER_1_SHA256) ASSET_MEMBER_1_SHA256=$value ;;
		ASSET_MEMBER_2) ASSET_MEMBER_2=$value ;;
		ASSET_MEMBER_2_SHA256) ASSET_MEMBER_2_SHA256=$value ;;
		ASSET_MEMBER_3) ASSET_MEMBER_3=$value ;;
		ASSET_MEMBER_3_SHA256) ASSET_MEMBER_3_SHA256=$value ;;
		ASSET_MEMBER_4) ASSET_MEMBER_4=$value ;;
		ASSET_MEMBER_4_SHA256) ASSET_MEMBER_4_SHA256=$value ;;
		ASSET_MEMBER_5) ASSET_MEMBER_5=$value ;;
		ASSET_MEMBER_5_SHA256) ASSET_MEMBER_5_SHA256=$value ;;
		ASSET_MEMBER_6) ASSET_MEMBER_6=$value ;;
		ASSET_MEMBER_6_SHA256) ASSET_MEMBER_6_SHA256=$value ;;
		ASSET_MEMBER_7) ASSET_MEMBER_7=$value ;;
		ASSET_MEMBER_7_SHA256) ASSET_MEMBER_7_SHA256=$value ;;
		ASSET_MEMBER_8) ASSET_MEMBER_8=$value ;;
		ASSET_MEMBER_8_SHA256) ASSET_MEMBER_8_SHA256=$value ;;
		TAILWIND_VERSION) TAILWIND_VERSION=$value ;;
		TAILWIND_PACKAGE_INTEGRITY) TAILWIND_PACKAGE_INTEGRITY=$value ;;
		TAILWIND_CLI_PACKAGE_INTEGRITY) TAILWIND_CLI_PACKAGE_INTEGRITY=$value ;;
		NODE_VERSION) NODE_VERSION=$value ;;
		NPM_VERSION) NPM_VERSION=$value ;;
		PLAYWRIGHT_VERSION) PLAYWRIGHT_VERSION=$value ;;
		AXE_PLAYWRIGHT_VERSION) AXE_PLAYWRIGHT_VERSION=$value ;;
		ACTIONLINT_VERSION) ACTIONLINT_VERSION=$value ;;
		*) die "unknown lock key: $key" ;;
	esac
done <"$lock_file"

require_value() {
	[ -n "$2" ] || die "missing lock key: $1"
}

require_sha256() {
	case "$2" in
		''|*[!0-9a-f]*) die "$1 must be a lowercase SHA-256" ;;
	esac
	[ "${#2}" -eq 64 ] || die "$1 must be a 64-character SHA-256"
}

validate_asset_member_path() {
	member=$1
	case "$member" in
		''|.|..|/*|*/|*//*|./*|*/./*|*/.|../*|*/../*|*/..|-*|*[!A-Za-z0-9_./-]*)
			die "invalid asset member: $member"
			;;
	esac
}

require_value DEX_COMMIT "$DEX_COMMIT"
case "$DEX_COMMIT" in
	*[!0-9a-f]*) die "DEX_COMMIT must be a lowercase commit SHA" ;;
esac
[ "${#DEX_COMMIT}" -eq 40 ] || die "DEX_COMMIT must be a 40-character commit SHA"
require_value DEX_IMAGE "$DEX_IMAGE"
require_value DEX_SERVER_VERSION "$DEX_SERVER_VERSION"
require_value DEX_SOURCE_URL "$DEX_SOURCE_URL"
require_value DEX_SOURCE_FILENAME "$DEX_SOURCE_FILENAME"
case "$DEX_SOURCE_FILENAME" in
	''|/*|*/*|.|..) die "invalid Dex source filename: $DEX_SOURCE_FILENAME" ;;
esac
require_value DEX_SOURCE_SHA256 "$DEX_SOURCE_SHA256"
require_sha256 DEX_SOURCE_SHA256 "$DEX_SOURCE_SHA256"
require_value DEX_BASE_X_MOD_VERSION "$DEX_BASE_X_MOD_VERSION"
require_value DEX_X_MOD_VERSION "$DEX_X_MOD_VERSION"
require_value DEX_BASE_API_GRPC_VERSION "$DEX_BASE_API_GRPC_VERSION"
require_value DEX_API_GRPC_VERSION "$DEX_API_GRPC_VERSION"
require_value GOSHTOSO_MODULE "$GOSHTOSO_MODULE"
require_value GOSHTOSO_VERSION "$GOSHTOSO_VERSION"
require_value GOSHTOSO_MODULE_SUM "$GOSHTOSO_MODULE_SUM"
require_value GOSHTOSO_GOMOD_SUM "$GOSHTOSO_GOMOD_SUM"
require_value GOSHTOSO_THEME_SHA256 "$GOSHTOSO_THEME_SHA256"
require_sha256 GOSHTOSO_THEME_SHA256 "$GOSHTOSO_THEME_SHA256"
require_value GOSHTOSO_CATALOG_SHA256 "$GOSHTOSO_CATALOG_SHA256"
require_sha256 GOSHTOSO_CATALOG_SHA256 "$GOSHTOSO_CATALOG_SHA256"
require_value ARAIHU_ASSETS_VERSION "$ARAIHU_ASSETS_VERSION"
require_value ASSETS_ARCHIVE_URL "$ASSETS_ARCHIVE_URL"
require_value ASSETS_ARCHIVE_FILENAME "$ASSETS_ARCHIVE_FILENAME"
case "$ASSETS_ARCHIVE_FILENAME" in
	''|/*|*/*|.|..) die "invalid Assets archive filename: $ASSETS_ARCHIVE_FILENAME" ;;
esac
require_value ASSETS_ARCHIVE_SHA256 "$ASSETS_ARCHIVE_SHA256"
require_sha256 ASSETS_ARCHIVE_SHA256 "$ASSETS_ARCHIVE_SHA256"
require_value ASSETS_RELEASE_SUMS_URL "$ASSETS_RELEASE_SUMS_URL"
require_value ASSETS_RELEASE_SUMS_FILENAME "$ASSETS_RELEASE_SUMS_FILENAME"
case "$ASSETS_RELEASE_SUMS_FILENAME" in
	''|/*|*/*|.|..) die "invalid Assets SHA256SUMS filename: $ASSETS_RELEASE_SUMS_FILENAME" ;;
esac
require_value ASSETS_RELEASE_SUMS_SHA256 "$ASSETS_RELEASE_SUMS_SHA256"
require_sha256 ASSETS_RELEASE_SUMS_SHA256 "$ASSETS_RELEASE_SUMS_SHA256"
require_value ASSETS_MEMBER_MANIFEST_URL "$ASSETS_MEMBER_MANIFEST_URL"
require_value ASSETS_MEMBER_MANIFEST_FILENAME "$ASSETS_MEMBER_MANIFEST_FILENAME"
case "$ASSETS_MEMBER_MANIFEST_FILENAME" in
	''|/*|*/*|.|..) die "invalid Assets member manifest filename: $ASSETS_MEMBER_MANIFEST_FILENAME" ;;
esac
require_value ASSETS_MEMBER_MANIFEST_SHA256 "$ASSETS_MEMBER_MANIFEST_SHA256"
require_sha256 ASSETS_MEMBER_MANIFEST_SHA256 "$ASSETS_MEMBER_MANIFEST_SHA256"
require_value ASSET_MEMBER_COUNT "$ASSET_MEMBER_COUNT"
[ "$ASSET_MEMBER_COUNT" -eq 8 ] || die "ASSET_MEMBER_COUNT must be 8"
require_value TAILWIND_VERSION "$TAILWIND_VERSION"
require_value TAILWIND_PACKAGE_INTEGRITY "$TAILWIND_PACKAGE_INTEGRITY"
require_value TAILWIND_CLI_PACKAGE_INTEGRITY "$TAILWIND_CLI_PACKAGE_INTEGRITY"
require_value NODE_VERSION "$NODE_VERSION"
require_value NPM_VERSION "$NPM_VERSION"
require_value PLAYWRIGHT_VERSION "$PLAYWRIGHT_VERSION"
require_value AXE_PLAYWRIGHT_VERSION "$AXE_PLAYWRIGHT_VERSION"
require_value ACTIONLINT_VERSION "$ACTIONLINT_VERSION"

for member_hash in \
	"$ASSET_MEMBER_1_SHA256" \
	"$ASSET_MEMBER_2_SHA256" \
	"$ASSET_MEMBER_3_SHA256" \
	"$ASSET_MEMBER_4_SHA256" \
	"$ASSET_MEMBER_5_SHA256" \
	"$ASSET_MEMBER_6_SHA256" \
	"$ASSET_MEMBER_7_SHA256" \
	"$ASSET_MEMBER_8_SHA256"; do
	require_sha256 ASSET_MEMBER_SHA256 "$member_hash"
done
seen_members=
for member in \
	"$ASSET_MEMBER_1" \
	"$ASSET_MEMBER_2" \
	"$ASSET_MEMBER_3" \
	"$ASSET_MEMBER_4" \
	"$ASSET_MEMBER_5" \
	"$ASSET_MEMBER_6" \
	"$ASSET_MEMBER_7" \
	"$ASSET_MEMBER_8"; do
	validate_asset_member_path "$member"
	case " $seen_members " in
		*" $member "*) die "duplicate asset member: $member" ;;
	esac
	seen_members="$seen_members$member "
done

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"
command -v go >/dev/null 2>&1 || die "go is required"

fetch_cache=${FETCH_CACHE:-$repo/.cache/sources}
downloads="$fetch_cache/downloads"
mkdir -p "$downloads"

hash_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		die "sha256 tool is required"
	fi
}

download_file() {
	url=$1
	destination=$2
	if [ -e "$destination" ]; then
		[ -f "$destination" ] || die "download cache is not a regular file: $destination"
		return
	fi
	temporary="$destination.tmp.$$"
	curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$temporary" || \
		die "download failed: $url"
	mv "$temporary" "$destination"
}

verify_file() {
	file=$1
	expected=$2
	message=$3
	actual=$(hash_file "$file")
	[ "$actual" = "$expected" ] || die "$message (expected $expected, got $actual)"
}

validate_archive() {
	archive=$1
	kind=$2
	listing=$3
	verbose=$4
	canonical_listing="$listing.canonical"
	tar -tzf "$archive" >"$listing" || die "$kind archive cannot be listed"
	: >"$canonical_listing"
	while IFS= read -r member || [ -n "$member" ]; do
		case "$member" in
			''|.|..|/*|*//*|./*|*/./*|*/.|../*|*/../*|*/..)
				die "$kind archive contains unsafe member: $member"
				;;
		esac
		canonical_member=$member
		case "$canonical_member" in
			*/) canonical_member=${canonical_member%/} ;;
		esac
		[ -n "$canonical_member" ] || die "$kind archive contains unsafe member: $member"
		printf '%s\n' "$canonical_member" >>"$canonical_listing"
	done <"$listing"
	duplicate=$(sort "$canonical_listing" | uniq -d | sed -n '1p')
	[ -z "$duplicate" ] || die "$kind archive contains duplicate destination: $duplicate"
	tar -tvzf "$archive" >"$verbose" || die "$kind archive metadata cannot be read"
	while IFS= read -r entry || [ -n "$entry" ]; do
		entry_type=$(printf '%s' "$entry" | cut -c 1)
		case "$entry_type" in
			l|h) die "$kind archive contains a symlink or hard link" ;;
		esac
	done <"$verbose"
}

release_sum() {
	file=$1
	filename=$2
	label=$3
	count=$(awk -v target="$filename" '$2 == target {count++} END {print count + 0}' "$file")
	[ "$count" -eq 1 ] || die "$label entry is missing or duplicated"
	awk -v target="$filename" '$2 == target {print $1; exit}' "$file"
}

install_asset_tree() {
	stage=$1
	destination=$2
	if [ ! -e "$destination" ]; then
		mv "$stage" "$destination"
		return
	fi
	for member in \
		"$ASSET_MEMBER_1" \
		"$ASSET_MEMBER_2" \
		"$ASSET_MEMBER_3" \
		"$ASSET_MEMBER_4" \
		"$ASSET_MEMBER_5" \
		"$ASSET_MEMBER_6" \
		"$ASSET_MEMBER_7" \
		"$ASSET_MEMBER_8"; do
		mkdir -p "$destination/$(dirname "$member")"
		mv "$stage/$member" "$destination/$member"
	done
}

install_dex_tree() {
	stage=$1
	destination=$2
	if [ ! -e "$destination" ]; then
		mv "$stage" "$destination"
		return
	fi
	for template in \
		approval.html \
		device.html \
		device_success.html \
		error.html \
		home.html \
		login.html \
		logout.html \
		oob.html \
		password.html \
		totp_verify.html \
		webauthn_verify.html; do
		mkdir -p "$destination/web/templates"
		mv "$stage/web/templates/$template" "$destination/web/templates/$template"
	done
}

dex_archive="$downloads/$DEX_SOURCE_FILENAME"
assets_archive="$downloads/$ASSETS_ARCHIVE_FILENAME"
release_sums="$downloads/$ASSETS_RELEASE_SUMS_FILENAME"
member_manifest="$downloads/$ASSETS_MEMBER_MANIFEST_FILENAME"
download_file "$DEX_SOURCE_URL" "$dex_archive"
verify_file "$dex_archive" "$DEX_SOURCE_SHA256" 'Dex source checksum mismatch'

download_file "$ASSETS_RELEASE_SUMS_URL" "$release_sums"
verify_file "$release_sums" "$ASSETS_RELEASE_SUMS_SHA256" 'Assets SHA256SUMS checksum mismatch'
release_archive_digest=$(release_sum "$release_sums" "$ASSETS_ARCHIVE_FILENAME" 'Assets archive')
[ "$release_archive_digest" = "$ASSETS_ARCHIVE_SHA256" ] || \
	die 'Assets archive checksum identity mismatch'
download_file "$ASSETS_ARCHIVE_URL" "$assets_archive"
verify_file "$assets_archive" "$ASSETS_ARCHIVE_SHA256" 'Assets archive checksum mismatch'
release_manifest_digest=$(release_sum "$release_sums" "$ASSETS_MEMBER_MANIFEST_FILENAME" 'Assets member manifest')
[ "$release_manifest_digest" = "$ASSETS_MEMBER_MANIFEST_SHA256" ] || \
	die 'Assets member manifest checksum identity mismatch'
download_file "$ASSETS_MEMBER_MANIFEST_URL" "$member_manifest"
verify_file "$member_manifest" "$ASSETS_MEMBER_MANIFEST_SHA256" 'Assets member manifest checksum mismatch'

dex_listing="$fetch_cache/.dex-members.$$"
dex_verbose="$fetch_cache/.dex-verbose.$$"
assets_listing="$fetch_cache/.assets-members.$$"
assets_verbose="$fetch_cache/.assets-verbose.$$"
validate_archive "$dex_archive" 'Dex source' "$dex_listing" "$dex_verbose"
validate_archive "$assets_archive" 'Assets' "$assets_listing" "$assets_verbose"

dex_prefix=dex-$DEX_COMMIT/
module_version() {
	member=$1
	module=$2
	label=$3
	count=$(tar -xOzf "$dex_archive" "$dex_prefix$member" |
		awk -v module="$module" '$1 == module { count++ } END { print count + 0 }')
	[ "$count" -eq 1 ] || die "$label baseline is missing or duplicated"
	tar -xOzf "$dex_archive" "$dex_prefix$member" |
		awk -v module="$module" '$1 == module { print $2; exit }'
}

[ "$(module_version go.mod golang.org/x/mod 'Dex x/mod')" = "$DEX_BASE_X_MOD_VERSION" ] ||
	die 'Dex x/mod baseline changed; review security pins manually'
[ "$(module_version api/v2/go.mod google.golang.org/grpc 'Dex API gRPC')" = "$DEX_BASE_API_GRPC_VERSION" ] ||
	die 'Dex API gRPC baseline changed; review security pins manually'

assets_stage="$fetch_cache/.assets-stage.$$"
dex_stage="$fetch_cache/.dex-stage.$$"
catalog_work="$fetch_cache/.catalog-work.$$"
gomod_cache="$catalog_work/gomodcache"
gocache="$catalog_work/gocache"
mkdir -p "$assets_stage" "$dex_stage/web/templates" "$catalog_work" "$gomod_cache"
cleanup() {
	chmod -R u+w "$catalog_work" 2>/dev/null || true
	rm -rf "$assets_stage" "$dex_stage" "$catalog_work" "$dex_listing" "$dex_listing.canonical" \
		"$dex_verbose" "$assets_listing" "$assets_listing.canonical" "$assets_verbose"
}
trap cleanup EXIT HUP INT TERM

for member in \
	"$ASSET_MEMBER_1" \
	"$ASSET_MEMBER_2" \
	"$ASSET_MEMBER_3" \
	"$ASSET_MEMBER_4" \
	"$ASSET_MEMBER_5" \
	"$ASSET_MEMBER_6" \
	"$ASSET_MEMBER_7" \
	"$ASSET_MEMBER_8"; do
	count=$(grep -Fxc "$member" "$assets_listing" || true)
	[ "$count" -eq 1 ] || die "Assets member is missing or duplicated: $member"
	manifest_count=$(awk -v target="$member" '$2 == target {count++} END {print count + 0}' "$member_manifest")
	[ "$manifest_count" -eq 1 ] || die "Assets member manifest entry is missing or duplicated: $member"
	member_expected=$(awk -v target="$member" '$2 == target {print $1; exit}' "$member_manifest")
	case "$member" in
		"$ASSET_MEMBER_1") member_lock_hash=$ASSET_MEMBER_1_SHA256 ;;
		"$ASSET_MEMBER_2") member_lock_hash=$ASSET_MEMBER_2_SHA256 ;;
		"$ASSET_MEMBER_3") member_lock_hash=$ASSET_MEMBER_3_SHA256 ;;
		"$ASSET_MEMBER_4") member_lock_hash=$ASSET_MEMBER_4_SHA256 ;;
		"$ASSET_MEMBER_5") member_lock_hash=$ASSET_MEMBER_5_SHA256 ;;
		"$ASSET_MEMBER_6") member_lock_hash=$ASSET_MEMBER_6_SHA256 ;;
		"$ASSET_MEMBER_7") member_lock_hash=$ASSET_MEMBER_7_SHA256 ;;
		"$ASSET_MEMBER_8") member_lock_hash=$ASSET_MEMBER_8_SHA256 ;;
		*) die "unmapped asset member: $member" ;;
	esac
	[ "$member_expected" = "$member_lock_hash" ] || \
		die "Assets member checksum identity mismatch: $member"
	asset_entry=$(tar -tvzf "$assets_archive" "$member" | sed -n '1p') || \
		die "Assets member cannot be read: $member"
	asset_type=$(printf '%s' "$asset_entry" | cut -c 1)
	[ "$asset_type" = '-' ] || die "Assets member is not a regular file: $member"
	target="$assets_stage/$member"
	mkdir -p "$(dirname "$target")"
	temporary="$target.tmp.$$"
	tar -xOzf "$assets_archive" "$member" >"$temporary" || \
		die "Assets member cannot be extracted: $member"
	verify_file "$temporary" "$member_lock_hash" 'Assets member checksum mismatch'
	mv "$temporary" "$target"
done
install_asset_tree "$assets_stage" "$fetch_cache/assets"
assets_stage=

for template in \
	approval.html \
	device.html \
	device_success.html \
	error.html \
	home.html \
	login.html \
	logout.html \
	oob.html \
	password.html \
	totp_verify.html \
	webauthn_verify.html; do
	dex_member=${dex_prefix}web/templates/$template
	count=$(grep -Fxc "$dex_member" "$dex_listing" || true)
	[ "$count" -eq 1 ] || die "Dex template is missing or duplicated: $template"
	dex_entry=$(tar -tvzf "$dex_archive" "$dex_member" | sed -n '1p') || \
		die "Dex template cannot be read: $template"
	dex_type=$(printf '%s' "$dex_entry" | cut -c 1)
	[ "$dex_type" = '-' ] || die "Dex template is not a regular file: $template"
	target="$dex_stage/web/templates/$template"
	temporary="$target.tmp.$$"
	tar -xOzf "$dex_archive" "$dex_member" >"$temporary" || \
		die "Dex template cannot be extracted: $template"
	mv "$temporary" "$target"
done
install_dex_tree "$dex_stage" "$fetch_cache/dex"
dex_stage=

cat >"$catalog_work/go.mod" <<EOF
module araihu-dex-catalog

go 1.27.3

require $GOSHTOSO_MODULE $GOSHTOSO_VERSION
EOF
cat >"$catalog_work/catalog.go" <<'EOF'
package main

import (
	"fmt"

	"github.com/araihu/goshtoso/themes"
)

func main() {
	for _, theme := range themes.BuiltIn() {
		fmt.Printf("%s\t%s\n", theme.Key, theme.Label)
	}
}
EOF

(cd "$catalog_work" && GOWORK=off GOMODCACHE="$gomod_cache" GOCACHE="$gocache" \
	go mod download -json "$GOSHTOSO_MODULE@$GOSHTOSO_VERSION") >"$catalog_work/module.json" || \
	die 'Goshtoso module download failed'
module_sum=$(awk -F'"' '/"Sum":/ {print $4; exit}' "$catalog_work/module.json")
gomod_sum=$(awk -F'"' '/"GoModSum":/ {print $4; exit}' "$catalog_work/module.json")
[ "$module_sum" = "$GOSHTOSO_MODULE_SUM" ] || die 'Goshtoso module checksum mismatch'
[ "$gomod_sum" = "$GOSHTOSO_GOMOD_SUM" ] || die 'Goshtoso go.mod checksum mismatch'

theme_tmp="$fetch_cache/.goshtoso-theme.$$"
GOWORK=off GOMODCACHE="$gomod_cache" GOCACHE="$gocache" \
	go run "$GOSHTOSO_MODULE/cmd/goshtoso@$GOSHTOSO_VERSION" \
	-theme -out="$theme_tmp" || die 'Goshtoso theme generation failed'
verify_file "$theme_tmp" "$GOSHTOSO_THEME_SHA256" 'Goshtoso theme checksum mismatch'
mkdir -p "$fetch_cache/goshtoso"
mv "$theme_tmp" "$fetch_cache/goshtoso/goshtoso-theme.css"
theme_tmp=

catalog_tmp="$fetch_cache/.theme-catalog.$$"
(cd "$catalog_work" && GOWORK=off GOMODCACHE="$gomod_cache" GOCACHE="$gocache" \
	go run -mod=mod ./catalog.go >"$catalog_tmp") || \
	die 'Goshtoso catalog generation failed'
verify_file "$catalog_tmp" "$GOSHTOSO_CATALOG_SHA256" 'Goshtoso theme catalog checksum mismatch'
mv "$catalog_tmp" "$fetch_cache/goshtoso/theme-catalog.txt"
catalog_tmp=

printf '%s\n' "fetch-sources: verified Dex $DEX_COMMIT, Goshtoso $GOSHTOSO_VERSION, Assets $ARAIHU_ASSETS_VERSION"
