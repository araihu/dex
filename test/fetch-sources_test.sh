#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
cleanup() {
	chmod -R u+w "$tmp" 2>/dev/null || true
	rm -rf "$tmp"
}
trap cleanup EXIT

if [ ! -f "$repo/versions.env" ]; then
	"$repo/scripts/fetch-sources.sh"
	exit 1
fi

digest() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

dex_commit=ab64ed778070e983cbb10cfc07ea4bb397d14312
dex_root="$tmp/dex-tree/dex-$dex_commit"
mkdir -p "$dex_root/web/templates"
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
	printf 'fixture %s\n' "$template" >"$dex_root/web/templates/$template"
done
dex_archive="$tmp/dex.tar.gz"
tar -czf "$dex_archive" -C "$tmp/dex-tree" "dex-$dex_commit"
dex_hash=$(digest "$dex_archive")

asset_tree="$tmp/assets-tree"
mkdir -p "$asset_tree/brand/araihu/logo" \
	"$asset_tree/platform/web/araihu" \
	"$asset_tree/icons/ui" \
	"$asset_tree/licenses"
printf 'fixture notice\n' >"$asset_tree/NOTICE"
printf 'fixture logo\n' >"$asset_tree/brand/araihu/logo/adaptive-transparent-optical.svg"
printf '<svg>fixture</svg>\n' >"$asset_tree/platform/web/araihu/favicon.svg"
printf 'fixture png\n' >"$asset_tree/platform/web/araihu/favicon-32.png"
printf 'fixture sprite\n' >"$asset_tree/icons/ui/sprite.svg"
printf 'Apache fixture\n' >"$asset_tree/licenses/Apache-2.0.txt"
printf 'Heroicons fixture\n' >"$asset_tree/licenses/heroicons-MIT.txt"
printf 'Developer icons fixture\n' >"$asset_tree/licenses/developer-icons-MIT.txt"
asset_members='NOTICE brand/araihu/logo/adaptive-transparent-optical.svg platform/web/araihu/favicon.svg platform/web/araihu/favicon-32.png icons/ui/sprite.svg licenses/Apache-2.0.txt licenses/heroicons-MIT.txt licenses/developer-icons-MIT.txt'
asset_manifest="$tmp/checksums.txt"
(
	cd "$asset_tree"
	for member in $asset_members; do
		printf '%s  %s\n' "$(digest "$asset_tree/$member")" "$member"
	done
) >"$asset_manifest"
asset_archive="$tmp/araihu-assets-v0.2.3.tar.gz"
tar -czf "$asset_archive" -C "$asset_tree" $asset_members
asset_hash=$(digest "$asset_archive")
manifest_hash=$(digest "$asset_manifest")
release_sums="$tmp/SHA256SUMS"
{
	printf '%s  araihu-assets-v0.2.3.tar.gz\n' "$asset_hash"
	printf '%s  checksums.txt\n' "$manifest_hash"
} >"$release_sums"
release_sums_hash=$(digest "$release_sums")

member_1_hash=$(digest "$asset_tree/NOTICE")
member_2_hash=$(digest "$asset_tree/brand/araihu/logo/adaptive-transparent-optical.svg")
member_3_hash=$(digest "$asset_tree/platform/web/araihu/favicon.svg")
member_4_hash=$(digest "$asset_tree/platform/web/araihu/favicon-32.png")
member_5_hash=$(digest "$asset_tree/icons/ui/sprite.svg")
member_6_hash=$(digest "$asset_tree/licenses/Apache-2.0.txt")
member_7_hash=$(digest "$asset_tree/licenses/heroicons-MIT.txt")
member_8_hash=$(digest "$asset_tree/licenses/developer-icons-MIT.txt")

write_lock() {
	output=$1
	dex_url=$2
	dex_digest=$3
	assets_url=$4
	assets_digest=$5
	sums_url=$6
	sums_digest=$7
	sed \
		-e "s|^DEX_SOURCE_URL=.*|DEX_SOURCE_URL=$dex_url|" \
		-e "s|^DEX_SOURCE_SHA256=.*|DEX_SOURCE_SHA256=$dex_digest|" \
		-e "s|^ASSETS_ARCHIVE_URL=.*|ASSETS_ARCHIVE_URL=$assets_url|" \
		-e "s|^ASSETS_ARCHIVE_SHA256=.*|ASSETS_ARCHIVE_SHA256=$assets_digest|" \
		-e "s|^ASSETS_RELEASE_SUMS_URL=.*|ASSETS_RELEASE_SUMS_URL=$sums_url|" \
		-e "s|^ASSETS_RELEASE_SUMS_SHA256=.*|ASSETS_RELEASE_SUMS_SHA256=$sums_digest|" \
		-e "s|^ASSETS_MEMBER_MANIFEST_URL=.*|ASSETS_MEMBER_MANIFEST_URL=file://$asset_manifest|" \
		-e "s|^ASSETS_MEMBER_MANIFEST_SHA256=.*|ASSETS_MEMBER_MANIFEST_SHA256=$manifest_hash|" \
		-e "s|^ASSET_MEMBER_1_SHA256=.*|ASSET_MEMBER_1_SHA256=$member_1_hash|" \
		-e "s|^ASSET_MEMBER_2_SHA256=.*|ASSET_MEMBER_2_SHA256=$member_2_hash|" \
		-e "s|^ASSET_MEMBER_3_SHA256=.*|ASSET_MEMBER_3_SHA256=$member_3_hash|" \
		-e "s|^ASSET_MEMBER_4_SHA256=.*|ASSET_MEMBER_4_SHA256=$member_4_hash|" \
		-e "s|^ASSET_MEMBER_5_SHA256=.*|ASSET_MEMBER_5_SHA256=$member_5_hash|" \
		-e "s|^ASSET_MEMBER_6_SHA256=.*|ASSET_MEMBER_6_SHA256=$member_6_hash|" \
		-e "s|^ASSET_MEMBER_7_SHA256=.*|ASSET_MEMBER_7_SHA256=$member_7_hash|" \
		-e "s|^ASSET_MEMBER_8_SHA256=.*|ASSET_MEMBER_8_SHA256=$member_8_hash|" \
		"$repo/versions.env" >"$output"
}

write_lock "$tmp/fixture.env" \
	"file://$dex_archive" "$dex_hash" \
	"file://$asset_archive" "$asset_hash" \
	"file://$release_sums" "$release_sums_hash"

FETCH_CACHE="$tmp/cache" VERSIONS_FILE="$tmp/fixture.env" \
	"$repo/scripts/fetch-sources.sh"
test -f "$tmp/cache/dex/web/templates/webauthn_verify.html"
test -f "$tmp/cache/goshtoso/goshtoso-theme.css"
test -f "$tmp/cache/goshtoso/theme-catalog.txt"
test -f "$tmp/cache/assets/platform/web/araihu/favicon.svg"
test -f "$tmp/cache/assets/licenses/heroicons-MIT.txt"

printf 'corrupt\n' >>"$tmp/cache/downloads/dex.tar.gz"
if FETCH_CACHE="$tmp/cache" VERSIONS_FILE="$tmp/fixture.env" \
	"$repo/scripts/fetch-sources.sh" 2>"$tmp/dex-error"; then
	echo 'expected Dex checksum failure' >&2
	exit 1
fi
grep -F 'Dex source checksum mismatch' "$tmp/dex-error"

bad_release_sums="$tmp/bad-SHA256SUMS"
cp "$release_sums" "$bad_release_sums"
printf 'corrupt\n' >>"$bad_release_sums"
write_lock "$tmp/bad-release.env" \
	"file://$dex_archive" "$dex_hash" \
	"file://$asset_archive" "$asset_hash" \
	"file://$bad_release_sums" "$release_sums_hash"
if FETCH_CACHE="$tmp/bad-release-cache" VERSIONS_FILE="$tmp/bad-release.env" \
	"$repo/scripts/fetch-sources.sh" 2>"$tmp/release-error"; then
	echo 'expected Assets release checksum failure' >&2
	exit 1
fi
grep -F 'Assets SHA256SUMS checksum mismatch' "$tmp/release-error"

bad_asset_tree="$tmp/bad-assets-tree"
cp -R "$asset_tree" "$bad_asset_tree"
printf 'changed\n' >>"$bad_asset_tree/platform/web/araihu/favicon.svg"
bad_asset_archive="$tmp/bad-araihu-assets-v0.2.3.tar.gz"
tar -czf "$bad_asset_archive" -C "$bad_asset_tree" $asset_members
bad_asset_hash=$(digest "$bad_asset_archive")
bad_release_sums="$tmp/bad-assets-SHA256SUMS"
{
	printf '%s  araihu-assets-v0.2.3.tar.gz\n' "$bad_asset_hash"
	printf '%s  checksums.txt\n' "$manifest_hash"
} >"$bad_release_sums"
bad_release_sums_hash=$(digest "$bad_release_sums")
write_lock "$tmp/bad-member.env" \
	"file://$dex_archive" "$dex_hash" \
	"file://$bad_asset_archive" "$bad_asset_hash" \
	"file://$bad_release_sums" "$bad_release_sums_hash"
if FETCH_CACHE="$tmp/bad-member-cache" VERSIONS_FILE="$tmp/bad-member.env" \
	"$repo/scripts/fetch-sources.sh" 2>"$tmp/member-error"; then
	echo 'expected Assets member checksum failure' >&2
	exit 1
fi
grep -F 'Assets member checksum mismatch' "$tmp/member-error"

wrong_module_lock="$tmp/wrong-module-sum.env"
sed 's|^GOSHTOSO_MODULE_SUM=.*|GOSHTOSO_MODULE_SUM=h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=|' \
	"$tmp/fixture.env" >"$wrong_module_lock"
go_wrapper_dir="$tmp/go-wrapper"
mkdir -p "$go_wrapper_dir"
go_run_marker="$tmp/go-run-attempted"
real_go=$(command -v go)
cat >"$go_wrapper_dir/go" <<EOF
#!/bin/sh
for arg do
	if [ "\$arg" = run ]; then
		: >"$go_run_marker"
	fi
done
exec "$real_go" "\$@"
EOF
chmod +x "$go_wrapper_dir/go"
if PATH="$go_wrapper_dir:$PATH" FETCH_CACHE="$tmp/wrong-module-cache" \
	VERSIONS_FILE="$wrong_module_lock" \
	"$repo/scripts/fetch-sources.sh" 2>"$tmp/wrong-module-error"; then
	echo 'expected Goshtoso module checksum failure' >&2
	exit 1
fi
grep -F 'Goshtoso module checksum mismatch' "$tmp/wrong-module-error"
if [ -e "$go_run_marker" ]; then
	echo 'Goshtoso code ran before module checksum rejection' >&2
	exit 1
fi

duplicate_dot_archive="$tmp/duplicate-dot-assets.tar.gz"
tar -czf "$duplicate_dot_archive" -C "$asset_tree" \
	NOTICE ./NOTICE \
	brand/araihu/logo/adaptive-transparent-optical.svg \
	platform/web/araihu/favicon.svg \
	platform/web/araihu/favicon-32.png \
	icons/ui/sprite.svg \
	licenses/Apache-2.0.txt \
	licenses/heroicons-MIT.txt \
	licenses/developer-icons-MIT.txt
duplicate_dot_hash=$(digest "$duplicate_dot_archive")
duplicate_dot_sums="$tmp/duplicate-dot-SHA256SUMS"
{
	printf '%s  araihu-assets-v0.2.3.tar.gz\n' "$duplicate_dot_hash"
	printf '%s  checksums.txt\n' "$manifest_hash"
} >"$duplicate_dot_sums"
duplicate_dot_sums_hash=$(digest "$duplicate_dot_sums")
write_lock "$tmp/duplicate-dot.env" \
	"file://$dex_archive" "$dex_hash" \
	"file://$duplicate_dot_archive" "$duplicate_dot_hash" \
	"file://$duplicate_dot_sums" "$duplicate_dot_sums_hash"
if FETCH_CACHE="$tmp/duplicate-dot-cache" VERSIONS_FILE="$tmp/duplicate-dot.env" \
	"$repo/scripts/fetch-sources.sh" 2>"$tmp/duplicate-dot-error"; then
	echo 'expected dot-spelling archive rejection' >&2
	exit 1
fi
grep -F 'Assets archive contains unsafe member: ./NOTICE' "$tmp/duplicate-dot-error"

duplicate_separator_archive="$tmp/duplicate-separator-assets.tar.gz"
tar -czf "$duplicate_separator_archive" -C "$asset_tree" \
	NOTICE \
	brand/araihu/logo/adaptive-transparent-optical.svg \
	brand//araihu/logo/adaptive-transparent-optical.svg \
	platform/web/araihu/favicon.svg \
	platform/web/araihu/favicon-32.png \
	icons/ui/sprite.svg \
	licenses/Apache-2.0.txt \
	licenses/heroicons-MIT.txt \
	licenses/developer-icons-MIT.txt
duplicate_separator_hash=$(digest "$duplicate_separator_archive")
duplicate_separator_sums="$tmp/duplicate-separator-SHA256SUMS"
{
	printf '%s  araihu-assets-v0.2.3.tar.gz\n' "$duplicate_separator_hash"
	printf '%s  checksums.txt\n' "$manifest_hash"
} >"$duplicate_separator_sums"
duplicate_separator_sums_hash=$(digest "$duplicate_separator_sums")
write_lock "$tmp/duplicate-separator.env" \
	"file://$dex_archive" "$dex_hash" \
	"file://$duplicate_separator_archive" "$duplicate_separator_hash" \
	"file://$duplicate_separator_sums" "$duplicate_separator_sums_hash"
if FETCH_CACHE="$tmp/duplicate-separator-cache" VERSIONS_FILE="$tmp/duplicate-separator.env" \
	"$repo/scripts/fetch-sources.sh" 2>"$tmp/duplicate-separator-error"; then
	echo 'expected repeated-separator archive rejection' >&2
	exit 1
fi
grep -F 'Assets archive contains unsafe member: brand//araihu/logo/adaptive-transparent-optical.svg' \
	"$tmp/duplicate-separator-error"

sed '/^DEX_SOURCE_SHA256=/d' "$repo/versions.env" >"$tmp/unset-lock.env"
if VERSIONS_FILE="$tmp/unset-lock.env" FETCH_CACHE="$tmp/unset-lock-cache" \
	"$repo/scripts/fetch-sources.sh" 2>"$tmp/unset-error"; then
	echo 'expected unset-lock failure' >&2
	exit 1
fi
grep -F 'missing lock key: DEX_SOURCE_SHA256' "$tmp/unset-error"

{
	cat "$repo/versions.env"
	printf 'UNKNOWN_KEY=value\n'
} >"$tmp/unknown-key.env"
if VERSIONS_FILE="$tmp/unknown-key.env" FETCH_CACHE="$tmp/unknown-key-cache" \
	"$repo/scripts/fetch-sources.sh" 2>"$tmp/unknown-error"; then
	echo 'expected unknown-key failure' >&2
	exit 1
fi
grep -F 'unknown lock key: UNKNOWN_KEY' "$tmp/unknown-error"

printf '%s\n' 'fetch-sources fixtures: PASS'
