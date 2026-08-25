#!/bin/sh
set -eu

die() {
	printf '%s\n' "update-lock: $*" >&2
	exit 1
}

repo=${UPDATE_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
lock_file=$repo/versions.env
report_file=${UPDATE_REPORT_FILE:-$repo/.cache/update-report.md}
official_image=ghcr.io/dexidp/dex:master
official_repository=dexidp/dex
official_identity=https://github.com/dexidp/dex/.github/workflows/artifacts.yaml@refs/heads/master
official_issuer=https://token.actions.githubusercontent.com
case "$#" in
	0) mode=update ;;
	1)
		[ "$1" = --verify-lock ] || die 'usage: scripts/update-lock.sh [--verify-lock]'
		mode=verify
		;;
	*) die 'usage: scripts/update-lock.sh [--verify-lock]' ;;
esac

for command_name in cosign curl docker gh git jq npm tar; do
	command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
done
[ -f "$lock_file" ] || die "lock file not found: $lock_file"
git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1 || die 'repository HEAD is required'
if [ "$mode" = update ]; then
	[ -d "$repo/node_modules" ] || die 'node_modules is missing; run npm ci first'
	[ -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ] || \
		die 'tracked worktree must be clean before updating'
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/araihu-dex-update.XXXXXX")
install_started=0
install_complete=0
cleanup() {
	status=$?
	trap - EXIT HUP INT TERM
	if [ "$status" -ne 0 ] && [ "$install_started" -eq 1 ] && [ "$install_complete" -eq 0 ]; then
		if ! restore_install; then
			printf '%s\n' 'update-lock: failed to restore prior prepared paths' >&2
			status=1
		fi
	fi
	rm -rf "$work"
	exit "$status"
}
trap cleanup EXIT HUP INT TERM

lock_value() {
	key=$1
	count=$(awk -F= -v key="$key" '$1 == key { count++ } END { print count + 0 }' "$lock_file")
	[ "$count" -eq 1 ] || die "lock key must occur exactly once: $key"
	awk -v prefix="$key=" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' "$lock_file"
}

require_commit() {
	case "$1" in
		''|*[!0-9a-f]*) die "$2 must be a lowercase commit SHA" ;;
	esac
	[ "${#1}" -eq 40 ] || die "$2 must be a 40-character commit SHA"
}

require_digest() {
	case "$1" in
		sha256:*) value=${1#sha256:} ;;
		*) die "$2 must be a sha256 digest" ;;
	esac
	case "$value" in
		''|*[!0-9a-f]*) die "$2 must be a lowercase sha256 digest" ;;
	esac
	[ "${#value}" -eq 64 ] || die "$2 must be a 64-character sha256 digest"
}

hash_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		die 'sha256 tool is required'
	fi
}

snapshot_git_metadata() {
	destination=$1
	head_target=$(git -C "$repo" symbolic-ref -q HEAD || printf detached)
	{
		printf 'HEAD\t%s\n' "$(git -C "$repo" rev-parse HEAD)"
		printf 'symbolic-HEAD\t%s\n' "$head_target"
		git -C "$repo" for-each-ref --format='ref\t%(refname)\t%(objectname)'
		git -C "$repo" config --local --get-regexp '^remote\.' 2>/dev/null || :
	} | LC_ALL=C sort >"$destination" || die 'cannot snapshot Git metadata'
}

assert_git_metadata_unchanged() {
	snapshot_git_metadata "$work/git-metadata.current"
	cmp -s "$work/git-metadata.before" "$work/git-metadata.current" ||
		die 'Git HEAD, refs, tags, or remotes changed during preparation'
}

snapshot_git_metadata "$work/git-metadata.before"

write_prefixed_line() {
	file=$1
	prefix=$2
	replacement=$3
	count=$(awk -v prefix="$prefix" 'index($0, prefix) == 1 { count++ } END { print count + 0 }' "$file")
	[ "$count" -eq 1 ] || die "expected one $prefix line in ${file#$repo/}"
	temporary=$file.update.$$
	awk -v prefix="$prefix" -v replacement="$replacement" '
		index($0, prefix) == 1 { print replacement; next }
		{ print }
	' "$file" >"$temporary"
	cat "$temporary" >"$file"
	rm -f "$temporary"
}

template_inventory() {
	archive=$1
	commit=$2
	tar -tzf "$archive" |
		sed -n "s|^dex-$commit/web/templates/\\([^/]*\\.html\\)$|\\1|p" |
		LC_ALL=C sort
}

extract_template() {
	archive=$1
	commit=$2
	template=$3
	destination=$4
	tar -xOzf "$archive" "dex-$commit/web/templates/$template" >"$destination" ||
		die "cannot extract Dex template: $template"
}

extract_inline_script() {
	source=$1
	destination=$2
	awk '
		/<script([[:space:]]|>)/ {
			if (inside || count != 0) exit 2
			inside = 1
			count++
		}
		inside { print }
		/<\/script>/ { if (inside) inside = 0 }
		END { if (count != 1 || inside) exit 3 }
	' "$source" >"$destination" || die 'WebAuthn template must contain exactly one complete inline script'
}

old_commit=$(lock_value DEX_COMMIT)
old_image=$(lock_value DEX_IMAGE)
old_source_url=$(lock_value DEX_SOURCE_URL)
source_filename=$(lock_value DEX_SOURCE_FILENAME)
old_source_hash=$(lock_value DEX_SOURCE_SHA256)
require_commit "$old_commit" DEX_COMMIT
case "$old_image" in
	"$official_image"@*) old_digest=${old_image#*@} ;;
	*) die 'DEX_IMAGE must pin the official Dex master image' ;;
esac
require_digest "$old_digest" DEX_IMAGE
[ "$old_source_url" = "https://github.com/dexidp/dex/archive/$old_commit.tar.gz" ] ||
	die 'DEX_SOURCE_URL does not match DEX_COMMIT'
[ "$source_filename" = dex.tar.gz ] || die 'DEX_SOURCE_FILENAME must remain dex.tar.gz'

if [ "$mode" = verify ]; then
	new_commit=$old_commit
	new_digest=$old_digest
	new_image=$old_image
	manifest_ref=$old_image
else
	new_commit=$(gh api "repos/$official_repository/commits/master" --jq .sha) ||
		die 'cannot resolve Dex master commit'
	require_commit "$new_commit" 'resolved Dex commit'
	manifest_ref=$official_image
fi

manifest_json=$(docker buildx imagetools inspect "$manifest_ref" --format '{{json .Manifest}}') ||
	die 'cannot resolve Dex master image digest'
resolved_digest=$(printf '%s\n' "$manifest_json" | jq -er '.digest') ||
	die 'Dex image did not resolve to a digest'
if [ "$mode" = update ]; then
	new_digest=$resolved_digest
	new_image=$official_image@$new_digest
else
	[ "$resolved_digest" = "$new_digest" ] || die 'locked Dex image digest no longer resolves exactly'
fi
require_digest "$new_digest" 'resolved Dex image'
printf '%s\n' "$manifest_json" | jq -e --arg digest "$new_digest" '
	(.mediaType == "application/vnd.oci.image.index.v1+json"
	 or .mediaType == "application/vnd.docker.distribution.manifest.list.v2+json")
	and .digest == $digest
	and any(.manifests[]; .platform.os == "linux" and .platform.architecture == "amd64")
	and any(.manifests[]; .platform.os == "linux" and .platform.architecture == "arm64")
' >/dev/null || die 'Dex master digest is not the required multi-architecture index'

image_json=$(docker buildx imagetools inspect "$new_image" --format '{{json .Image}}') ||
	die 'cannot inspect Dex platform image metadata'
printf '%s\n' "$image_json" | jq -e --arg commit "$new_commit" '
	type == "object"
	and has("linux/amd64")
	and has("linux/arm64")
	and ([to_entries[].value.config.Labels["org.opencontainers.image.revision"]] as $labels
		| ($labels | length) > 0 and all($labels[]; . == $commit))
' >/dev/null || die 'OCI revision label does not match resolved Dex commit'

cosign verify \
	--certificate-identity "$official_identity" \
	--certificate-oidc-issuer "$official_issuer" \
	--output json "$new_image" >"$work/cosign.json" ||
	die 'official Dex image signature verification failed'
jq -e --arg digest "$new_digest" '
	[.[] | select(
		.critical.type == "https://sigstore.dev/cosign/sign/v1"
		and .critical.image["docker-manifest-digest"] == $digest
	)] | length > 0
' "$work/cosign.json" >/dev/null || die 'official Dex image signature subject mismatch'

gh attestation verify "oci://ghcr.io/dexidp/dex@$new_digest" \
	--repo "$official_repository" \
	--cert-identity "$official_identity" \
	--cert-oidc-issuer "$official_issuer" \
	--source-ref refs/heads/master \
	--source-digest "$new_commit" \
	--predicate-type https://slsa.dev/provenance/v1 \
	--format json >"$work/provenance.json" ||
	die 'official Dex provenance verification failed'
digest_hex=${new_digest#sha256:}
jq -e \
	--arg identity "$official_identity" \
	--arg issuer "$official_issuer" \
	--arg commit "$new_commit" \
	--arg digest "$digest_hex" '
	[.[] | select(
		.verificationResult.statement.predicateType == "https://slsa.dev/provenance/v1"
		and any(.verificationResult.statement.subject[];
			.name == "ghcr.io/dexidp/dex" and .digest.sha256 == $digest)
		and .verificationResult.signature.certificate.subjectAlternativeName == $identity
		and .verificationResult.signature.certificate.issuer == $issuer
		and .verificationResult.signature.certificate.githubWorkflowSHA == $commit
		and .verificationResult.signature.certificate.sourceRepositoryDigest == $commit
		and .verificationResult.signature.certificate.sourceRepositoryRef == "refs/heads/master"
	)] | length > 0
' "$work/provenance.json" >/dev/null || die 'official Dex provenance identity mismatch'

if [ "$mode" = verify ]; then
	assert_git_metadata_unchanged
	printf '%s\n' "update-lock: verified Dex $new_commit ($new_digest)"
	exit 0
fi

old_archive=$work/old-dex.tar.gz
new_archive=$work/new-dex.tar.gz
curl -fsSL --retry 3 --retry-delay 1 "$old_source_url" -o "$old_archive" ||
	die 'locked Dex source download failed'
[ "$(hash_file "$old_archive")" = "$old_source_hash" ] || die 'locked Dex source checksum mismatch'
new_source_url=https://github.com/dexidp/dex/archive/$new_commit.tar.gz
curl -fsSL --retry 3 --retry-delay 1 "$new_source_url" -o "$new_archive" ||
	die 'updated Dex source download failed'
new_source_hash=$(hash_file "$new_archive")

expected_inventory=$(printf '%s\n' \
	approval.html \
	device.html \
	device_success.html \
	error.html \
	footer.html \
	header.html \
	home.html \
	login.html \
	logout.html \
	oob.html \
	password.html \
	totp_verify.html \
	webauthn_verify.html)
old_inventory=$(template_inventory "$old_archive" "$old_commit") || die 'cannot list locked Dex source archive'
[ "$old_inventory" = "$expected_inventory" ] || die 'locked Dex template inventory changed'
new_inventory=$(template_inventory "$new_archive" "$new_commit") || die 'cannot list updated Dex source archive'
[ "$new_inventory" = "$expected_inventory" ] || die 'Dex template inventory changed'

for template in header.html footer.html webauthn_verify.html; do
	extract_template "$old_archive" "$old_commit" "$template" "$work/old-$template"
	extract_template "$new_archive" "$new_commit" "$template" "$work/new-$template"
done
extract_inline_script "$work/old-webauthn_verify.html" "$work/old-webauthn-script"
extract_inline_script "$work/new-webauthn_verify.html" "$work/new-webauthn-script"
cmp -s "$work/old-webauthn-script" "$work/new-webauthn-script" ||
	die 'WebAuthn script changed; refresh semantic evidence manually'

for template in header.html footer.html; do
	if ! git merge-file -p "$repo/src/$template" "$work/old-$template" "$work/new-$template" \
		>"$work/merged-$template"; then
		die "shared template rebase failed: $template"
	fi
done

stage=$work/stage
mkdir -p "$stage"
git -C "$repo" archive --format=tar HEAD | tar -xf - -C "$stage" || die 'cannot stage repository HEAD'
ln -s "$repo/node_modules" "$stage/node_modules"
mkdir -p "$stage/.cache"
mkdir -p "$stage/.cache/sources"
for cache_entry in assets downloads goshtoso; do
	if [ -e "$repo/.cache/sources/$cache_entry" ]; then
		cp -R "$repo/.cache/sources/$cache_entry" "$stage/.cache/sources/$cache_entry"
	fi
done
mkdir -p "$stage/.cache/sources/downloads"
cp "$new_archive" "$stage/.cache/sources/downloads/$source_filename"

stage_lock=$stage/versions.env
write_prefixed_line "$stage_lock" 'DEX_COMMIT=' "DEX_COMMIT=$new_commit"
write_prefixed_line "$stage_lock" 'DEX_IMAGE=' "DEX_IMAGE=$new_image"
write_prefixed_line "$stage_lock" 'DEX_SOURCE_URL=' "DEX_SOURCE_URL=$new_source_url"
write_prefixed_line "$stage_lock" 'DEX_SOURCE_SHA256=' "DEX_SOURCE_SHA256=$new_source_hash"
[ "$(sed -n '1p' "$stage/Dockerfile")" = "FROM $old_image" ] || die 'Dockerfile base does not match DEX_IMAGE'
write_prefixed_line "$stage/Dockerfile" 'FROM ' "FROM $new_image"
grep -F "$old_image" "$stage/test/image-overlay_test.sh" >/dev/null ||
	die 'image overlay fixture does not match DEX_IMAGE'
write_prefixed_line "$stage/test/image-overlay_test.sh" 'upstream=' "upstream='$new_image'"
grep -F "dex_commit=$old_commit" "$stage/test/fetch-sources_test.sh" >/dev/null ||
	die 'source fixture does not match DEX_COMMIT'
write_prefixed_line "$stage/test/fetch-sources_test.sh" 'dex_commit=' "dex_commit=$new_commit"
cp "$work/merged-header.html" "$stage/src/header.html"
cp "$work/merged-footer.html" "$stage/src/footer.html"

(cd "$stage" && scripts/fetch-sources.sh) || die 'updated source verification failed'
(cd "$stage" && npm run generate) || die 'updated generation failed'
(cd "$stage" && sh test/fetch-sources_test.sh) || die 'source fixture tests failed'
(cd "$stage" && sh test/entrypoint_test.sh) || die 'entrypoint tests failed'
(cd "$stage" && npm test) || die 'Node generation tests failed'

iid_file=$work/image.iid
(cd "$stage" && docker buildx build --load --iidfile "$iid_file" .) ||
	die 'updated local image build failed'
[ -s "$iid_file" ] || die 'updated local image ID was not recorded'
image_id=$(cat "$iid_file")
case "$image_id" in
	sha256:*) ;;
	*) die 'updated local image ID is invalid' ;;
esac
if [ -n "${UPDATE_IMAGE_OVERLAY_TEST:-}" ]; then
	image_overlay_test=$UPDATE_IMAGE_OVERLAY_TEST
else
	image_overlay_test=$stage/test/image-overlay_test.sh
fi
sh "$image_overlay_test" "$image_id" || die 'filesystem overlay drift checks failed'
(cd "$stage" && scripts/test-image.sh "$image_id") || die 'visual, semantic, or accessibility acceptance failed'

assert_git_metadata_unchanged

manifest_digest=$(hash_file "$stage/web/manifest.sha256")
report=$work/update-report.md
{
	printf '%s\n' '## Dex upstream update'
	printf '\n- Old commit: `%s`\n' "$old_commit"
	printf -- '- New commit: `%s`\n' "$new_commit"
	printf -- '- Old digest: `%s`\n' "$old_digest"
	printf -- '- New digest: `%s`\n' "$new_digest"
	printf -- '- WebAuthn script: unchanged\n'
	printf -- '- Generated manifest digest: `sha256:%s`\n' "$manifest_digest"
	printf -- '- Human screenshot review: required\n'
	printf '\nTemplate inventory:\n\n'
	printf '%s\n' "$expected_inventory" | while IFS= read -r template; do
		printf -- '- `%s`\n' "$template"
	done
} >"$report"

owned_files='versions.env
Dockerfile
src/header.html
src/footer.html
test/image-overlay_test.sh
test/fetch-sources_test.sh'
install_backup=$work/install-backup
mkdir -p "$install_backup/files"
for relative_file in $owned_files; do
	[ -f "$repo/$relative_file" ] || die "prepared path is missing: $relative_file"
	mkdir -p "$install_backup/files/$(dirname "$relative_file")"
	cp -p "$repo/$relative_file" "$install_backup/files/$relative_file" ||
		die "cannot back up prepared path: $relative_file"
done
[ -d "$repo/web" ] || die 'generated web tree is missing'
cp -R "$repo/web" "$install_backup/web" || die 'cannot back up generated web tree'
if [ -e "$repo/.cache/sources" ]; then
	[ -d "$repo/.cache/sources" ] || die 'source cache path is not a directory'
	cp -R "$repo/.cache/sources" "$install_backup/sources" || die 'cannot back up source cache'
	: >"$install_backup/sources.present"
fi
[ ! -d "$report_file" ] || die 'update report path is a directory'
if [ -e "$report_file" ]; then
	cp -p "$report_file" "$install_backup/report" || die 'cannot back up update report'
	: >"$install_backup/report.present"
fi

restore_install() {
	restore_status=0
	for relative_file in $owned_files; do
		mkdir -p "$repo/$(dirname "$relative_file")" || restore_status=1
		cp -p "$install_backup/files/$relative_file" "$repo/$relative_file" || restore_status=1
	done
	rm -rf "$repo/web" || restore_status=1
	cp -R "$install_backup/web" "$repo/web" || restore_status=1
	rm -rf "$repo/.cache/sources" || restore_status=1
	if [ -f "$install_backup/sources.present" ]; then
		mkdir -p "$repo/.cache" || restore_status=1
		cp -R "$install_backup/sources" "$repo/.cache/sources" || restore_status=1
	fi
	rm -f "$report_file" || restore_status=1
	if [ -f "$install_backup/report.present" ]; then
		mkdir -p "$(dirname "$report_file")" || restore_status=1
		cp -p "$install_backup/report" "$report_file" || restore_status=1
	fi
	[ "$restore_status" -eq 0 ]
}

install_checkpoint() {
	checkpoint=$1
	if [ "${UPDATE_TEST_INSTALL_FAIL_AT:-}" = "$checkpoint" ]; then
		die "injected install failure: $checkpoint"
	fi
}

install_started=1
for relative_file in $owned_files; do
	cp -p "$stage/$relative_file" "$repo/$relative_file" ||
		die "cannot install prepared path: $relative_file"
done
install_checkpoint after-files

rm -rf "$repo/web"
cp -R "$stage/web" "$repo/web" || die 'cannot install generated web tree'
install_checkpoint after-web

mkdir -p "$repo/.cache"
rm -rf "$repo/.cache/sources"
cp -R "$stage/.cache/sources" "$repo/.cache/sources" || die 'cannot install source cache'
install_checkpoint after-cache

mkdir -p "$(dirname "$report_file")"
cp -p "$report" "$report_file" || die 'cannot install update report'
install_checkpoint after-report

assert_git_metadata_unchanged
install_complete=1

printf '%s\n' "update-lock: prepared Dex $old_commit -> $new_commit ($new_digest)"
