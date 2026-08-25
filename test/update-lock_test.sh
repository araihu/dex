#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
script=$repo/scripts/update-lock.sh
tmp=$(mktemp -d "${TMPDIR:-/tmp}/araihu-dex-update-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

old_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
new_commit=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
old_digest=sha256:1111111111111111111111111111111111111111111111111111111111111111
new_digest=sha256:2222222222222222222222222222222222222222222222222222222222222222
templates='approval.html device.html device_success.html error.html footer.html header.html home.html login.html logout.html oob.html password.html totp_verify.html webauthn_verify.html'

fail() {
	printf '%s\n' "update-lock_test: $*" >&2
	exit 1
}

digest() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

make_archive() {
	commit=$1
	archive=$2
	header=$3
	footer=$4
	webauthn=$5
	extra=${6:-}
	tree=${archive%.tar.gz}
	root=$tree/dex-$commit/web/templates
	mkdir -p "$root"
	for template in $templates; do
		case "$template" in
			header.html) printf '%s\n' "$header" >"$root/$template" ;;
			footer.html) printf '%s\n' "$footer" >"$root/$template" ;;
			webauthn_verify.html)
				printf '%s\n' '<section>WebAuthn</section>' '<script>' "$webauthn" '</script>' >"$root/$template"
				;;
			*) printf '<section>%s</section>\n' "$template" >"$root/$template" ;;
		esac
	done
	if [ -n "$extra" ]; then
		printf '%s\n' '<section>unexpected</section>' >"$root/$extra"
	fi
	tar -czf "$archive" -C "$tree" "dex-$commit"
}

write_executable() {
	file=$1
	shift
	mkdir -p "$(dirname "$file")"
	printf '%s\n' "$@" >"$file"
	chmod +x "$file"
}

prepare_fake_commands() {
	bin=$1
	mkdir -p "$bin"
	write_executable "$bin/gh" \
		'#!/bin/sh' \
		'set -eu' \
		'printf "gh %s\n" "$*" >>"$UPDATE_TEST_LOG"' \
		'if [ "$1" = api ]; then' \
		'  printf "%s\n" "$FIXTURE_NEW_COMMIT"' \
		'  exit 0' \
		'fi' \
		'cat <<EOF' \
		'[{"verificationResult":{"statement":{"predicateType":"https://slsa.dev/provenance/v1","subject":[{"name":"ghcr.io/dexidp/dex","digest":{"sha256":"${FIXTURE_NEW_DIGEST#sha256:}"}}]},"signature":{"certificate":{"subjectAlternativeName":"https://github.com/dexidp/dex/.github/workflows/artifacts.yaml@refs/heads/master","issuer":"https://token.actions.githubusercontent.com","githubWorkflowSHA":"$FIXTURE_NEW_COMMIT","sourceRepositoryDigest":"$FIXTURE_NEW_COMMIT","sourceRepositoryRef":"refs/heads/master"}}}}]' \
		'EOF'
	write_executable "$bin/docker" \
		'#!/bin/sh' \
		'set -eu' \
		'printf "docker %s\n" "$*" >>"$UPDATE_TEST_LOG"' \
		'case "$*" in' \
		'  *".Manifest"*)' \
		'    printf "{\"mediaType\":\"application/vnd.oci.image.index.v1+json\",\"digest\":\"%s\",\"manifests\":[{\"platform\":{\"os\":\"linux\",\"architecture\":\"amd64\"}},{\"platform\":{\"os\":\"linux\",\"architecture\":\"arm64\"}}]}\n" "$FIXTURE_NEW_DIGEST"' \
		'    ;;' \
		'  *".Image"*)' \
		'    revision=${FIXTURE_REVISION:-$FIXTURE_NEW_COMMIT}' \
		'    printf "{\"linux/amd64\":{\"config\":{\"Labels\":{\"org.opencontainers.image.revision\":\"%s\"}}},\"linux/arm64\":{\"config\":{\"Labels\":{\"org.opencontainers.image.revision\":\"%s\"}}}}\n" "$revision" "$revision"' \
		'    ;;' \
		'  *"buildx build"*)' \
		'    while [ "$#" -gt 0 ]; do' \
		'      if [ "$1" = --iidfile ]; then printf "%s\n" sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc >"$2"; exit 0; fi' \
		'      shift' \
		'    done' \
		'    exit 1' \
		'    ;;' \
		'  *) exit 1 ;;' \
		'esac'
	write_executable "$bin/cosign" \
		'#!/bin/sh' \
		'set -eu' \
		'printf "cosign %s\n" "$*" >>"$UPDATE_TEST_LOG"' \
		'printf "[{\"critical\":{\"type\":\"https://sigstore.dev/cosign/sign/v1\",\"image\":{\"docker-manifest-digest\":\"%s\"}}}]\n" "$FIXTURE_NEW_DIGEST"'
	write_executable "$bin/curl" \
		'#!/bin/sh' \
		'set -eu' \
		'destination=' \
		'url=' \
		'while [ "$#" -gt 0 ]; do' \
		'  case "$1" in' \
		'    -o) destination=$2; shift 2 ;;' \
		'    http://*|https://*|file://*) url=$1; shift ;;' \
		'    *) shift ;;' \
		'  esac' \
		'done' \
		'printf "curl %s\n" "$url" >>"$UPDATE_TEST_LOG"' \
		'case "$url" in' \
		'  *"$FIXTURE_NEW_COMMIT"*) cp "$FIXTURE_NEW_ARCHIVE" "$destination" ;;' \
		'  *) cp "$FIXTURE_OLD_ARCHIVE" "$destination" ;;' \
		'esac'
	write_executable "$bin/npm" \
		'#!/bin/sh' \
		'set -eu' \
		'printf "npm %s\n" "$*" >>"$UPDATE_TEST_LOG"'
}

prepare_repository() {
	root=$1
	current_header=$2
	old_archive_hash=$(digest "$(dirname "$root")/old.tar.gz")
	mkdir -p "$root/scripts" "$root/src" "$root/test" "$root/web" "$root/node_modules" "$root/.cache/sources"
	cat >"$root/versions.env" <<EOF
DEX_COMMIT=$old_commit
DEX_IMAGE=ghcr.io/dexidp/dex:master@$old_digest
DEX_SOURCE_URL=https://github.com/dexidp/dex/archive/$old_commit.tar.gz
DEX_SOURCE_FILENAME=dex.tar.gz
DEX_SOURCE_SHA256=$old_archive_hash
EOF
	printf 'FROM ghcr.io/dexidp/dex:master@%s\n' "$old_digest" >"$root/Dockerfile"
	printf '%s\n' "$current_header" >"$root/src/header.html"
	printf '%s\n' 'footer base' 'footer overlay' >"$root/src/footer.html"
	printf "upstream='%s'\n" "ghcr.io/dexidp/dex:master@$old_digest" >"$root/test/image-overlay_test.sh"
	printf 'dex_commit=%s\n' "$old_commit" >"$root/test/fetch-sources_test.sh"
	printf '%s\n' '#!/bin/sh' 'set -eu' 'printf "fetch-sources\n" >>"$UPDATE_TEST_LOG"' >"$root/scripts/fetch-sources.sh"
	printf '%s\n' '#!/bin/sh' 'set -eu' 'printf "entrypoint-test\n" >>"$UPDATE_TEST_LOG"' >"$root/test/entrypoint_test.sh"
	printf '%s\n' '#!/bin/sh' 'set -eu' 'printf "image-overlay-test\n" >>"$UPDATE_TEST_LOG"' >"$root/test/image-overlay_test.sh.gate"
	printf '%s\n' '#!/bin/sh' 'set -eu' 'printf "real-image-test\n" >>"$UPDATE_TEST_LOG"' >"$root/scripts/test-image.sh"
	chmod +x "$root/scripts/fetch-sources.sh" "$root/test/entrypoint_test.sh" \
		"$root/test/image-overlay_test.sh.gate" "$root/scripts/test-image.sh"
	printf '%s\n' '{"name":"fixture","scripts":{"test":"true"}}' >"$root/package.json"
	printf '%s\n' '{"lockfileVersion":3}' >"$root/package-lock.json"
	printf '%s\n' 'fixture manifest' >"$root/web/manifest.sha256"
	printf '%s\n' '.cache/' 'node_modules/' >"$root/.gitignore"
	git -C "$root" init -q
	git -C "$root" config user.name 'Update Lock Test'
	git -C "$root" config user.email update-lock@example.invalid
	git -C "$root" add .
	git -C "$root" commit -qm fixture
	printf '%s\n' stale >"$root/.cache/sources/stale"
}

run_update() {
	case_dir=$1
	shift
	PATH="$case_dir/bin:$PATH" \
	UPDATE_ROOT="$case_dir/repo" \
	UPDATE_IMAGE_OVERLAY_TEST="$case_dir/repo/test/image-overlay_test.sh.gate" \
	UPDATE_TEST_LOG="$case_dir/commands.log" \
	FIXTURE_OLD_ARCHIVE="$case_dir/old.tar.gz" \
	FIXTURE_NEW_ARCHIVE="$case_dir/new.tar.gz" \
	FIXTURE_NEW_COMMIT="$(cat "$case_dir/new-commit")" \
	FIXTURE_NEW_DIGEST="$(cat "$case_dir/new-digest")" \
	"$@" "$script" >"$case_dir/stdout" 2>"$case_dir/stderr"
}

run_lock_verification() {
	case_dir=$1
	PATH="$case_dir/bin:$PATH" \
	UPDATE_ROOT="$case_dir/repo" \
	UPDATE_TEST_LOG="$case_dir/commands.log" \
	FIXTURE_OLD_ARCHIVE="$case_dir/old.tar.gz" \
	FIXTURE_NEW_ARCHIVE="$case_dir/new.tar.gz" \
	FIXTURE_NEW_COMMIT="$(cat "$case_dir/new-commit")" \
	FIXTURE_NEW_DIGEST="$(cat "$case_dir/new-digest")" \
	"$script" --verify-lock >"$case_dir/stdout" 2>"$case_dir/stderr"
}

expect_failure() {
	case_dir=$1
	expected=$2
	shift 2
	if run_update "$case_dir" "$@"; then
		fail "expected failure containing: $expected"
	fi
	grep -F "$expected" "$case_dir/stderr" >/dev/null || {
		sed -n '1,120p' "$case_dir/stderr" >&2
		fail "missing diagnostic: $expected"
	}
	[ -z "$(git -C "$case_dir/repo" status --short)" ] || fail 'failed update changed tracked files'
}

make_case() {
	name=$1
	case_dir=$tmp/$name
	mkdir -p "$case_dir"
	prepare_fake_commands "$case_dir/bin"
	: >"$case_dir/commands.log"
	printf '%s\n' "$new_commit" >"$case_dir/new-commit"
	printf '%s\n' "$new_digest" >"$case_dir/new-digest"
	printf '%s\n' "$case_dir"
}

case_dir=$(make_case revision-mismatch)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
expect_failure "$case_dir" 'OCI revision label does not match resolved Dex commit' \
	env FIXTURE_REVISION="$old_commit"

case_dir=$(make_case inventory-change)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";' unexpected.html
prepare_repository "$case_dir/repo" 'header base
header overlay'
expect_failure "$case_dir" 'Dex template inventory changed' env

case_dir=$(make_case shared-conflict)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'shared base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'upstream replacement' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'local replacement'
expect_failure "$case_dir" 'shared template rebase failed: header.html' env

case_dir=$(make_case webauthn-change)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "changed";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
expect_failure "$case_dir" 'WebAuthn script changed; refresh semantic evidence manually' env

case_dir=$(make_case no-op)
printf '%s\n' "$old_commit" >"$case_dir/new-commit"
printf '%s\n' "$old_digest" >"$case_dir/new-digest"
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
cp "$case_dir/old.tar.gz" "$case_dir/new.tar.gz"
prepare_repository "$case_dir/repo" 'header base
header overlay'
run_update "$case_dir" env
[ -z "$(git -C "$case_dir/repo" status --short)" ] || fail 'no-op update changed tracked files'
[ ! -e "$case_dir/repo/.cache/sources/stale" ] || fail 'update preserved stale source-cache content'
grep -F 'fetch-sources' "$case_dir/commands.log" >/dev/null
grep -F 'npm run generate' "$case_dir/commands.log" >/dev/null
grep -F 'npm test' "$case_dir/commands.log" >/dev/null
grep -F 'docker buildx build' "$case_dir/commands.log" >/dev/null
if grep -F 'docker buildx build --platform' "$case_dir/commands.log" >/dev/null; then
	fail 'local update build forced a non-native platform'
fi
grep -F 'image-overlay-test' "$case_dir/commands.log" >/dev/null
grep -F 'real-image-test' "$case_dir/commands.log" >/dev/null
grep -F 'cosign verify --certificate-identity https://github.com/dexidp/dex/.github/workflows/artifacts.yaml@refs/heads/master --certificate-oidc-issuer https://token.actions.githubusercontent.com' \
	"$case_dir/commands.log" >/dev/null
grep -F "gh attestation verify oci://ghcr.io/dexidp/dex@$old_digest --repo dexidp/dex --cert-identity https://github.com/dexidp/dex/.github/workflows/artifacts.yaml@refs/heads/master --cert-oidc-issuer https://token.actions.githubusercontent.com --source-ref refs/heads/master --source-digest $old_commit" \
	"$case_dir/commands.log" >/dev/null
grep -F 'WebAuthn script: unchanged' "$case_dir/repo/.cache/update-report.md" >/dev/null
grep -F 'Human screenshot review: required' "$case_dir/repo/.cache/update-report.md" >/dev/null
if grep -E '(gh pr|git push|git tag|docker push)' "$case_dir/commands.log" >/dev/null; then
	fail 'update-lock attempted a prohibited remote mutation'
fi

: >"$case_dir/commands.log"
run_lock_verification "$case_dir"
grep -F 'cosign verify' "$case_dir/commands.log" >/dev/null
grep -F 'gh attestation verify' "$case_dir/commands.log" >/dev/null
if grep -E '(gh api|docker buildx build|curl |npm |fetch-sources|image-test)' "$case_dir/commands.log" >/dev/null; then
	fail 'lock-only verification resolved or prepared an update'
fi

printf '%s\n' 'update-lock fixtures: PASS'
