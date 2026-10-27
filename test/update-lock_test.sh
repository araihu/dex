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
new_version=v2.46.0-20260806171424-bbbbbbbb
approved_prerelease_tag=v2.46.0-20260806171424-ab64ed77
approved_prerelease_commit=ab64ed778070e983cbb10cfc07ea4bb397d14312
approved_prerelease_digest=sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b
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
	mkdir -p "$tree/dex-$commit/api/v2"
    printf 'module github.com/dexidp/dex/v2\nrequire (\n golang.org/x/mod %s\n)\n' "${FIXTURE_SOURCE_X_MOD:-v0.37.0}" > "$tree/dex-$commit/go.mod"
    printf 'module github.com/dexidp/dex/api/v2\nrequire (\n google.golang.org/grpc %s\n)\n' "${FIXTURE_SOURCE_GRPC:-v1.82.0}" > "$tree/dex-$commit/api/v2/go.mod"
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
		'    version=${FIXTURE_VERSION:-$FIXTURE_NEW_VERSION}' \
		'    printf "{\"linux/amd64\":{\"config\":{\"Labels\":{\"org.opencontainers.image.revision\":\"%s\",\"org.opencontainers.image.version\":\"%s\"}}},\"linux/arm64\":{\"config\":{\"Labels\":{\"org.opencontainers.image.revision\":\"%s\",\"org.opencontainers.image.version\":\"%s\"}}}}\n" "$revision" "$version" "$revision" "$version"' \
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
		'if [ "$1" = verify-attestation ]; then' \
		'  statement=$(jq -cn --arg commit "$FIXTURE_NEW_COMMIT" --arg digest "${FIXTURE_NEW_DIGEST#sha256:}" '\''{"_type":"https://in-toto.io/Statement/v1","subject":[{"name":"ghcr.io/dexidp/dex","digest":{"sha256":$digest}}],"predicateType":"https://slsa.dev/provenance/v1","predicate":{"buildDefinition":{"externalParameters":{"workflow":{"repository":"https://github.com/dexidp/dex","ref":"refs/heads/master"}},"resolvedDependencies":[{"uri":"git+https://github.com/dexidp/dex@refs/heads/master","digest":{"gitCommit":$commit}}]},"runDetails":{"builder":{"id":"https://github.com/dexidp/dex/.github/workflows/artifacts.yaml@refs/heads/master"}}}}'\'')' \
		'  payload=$(printf "%s" "$statement" | base64 | tr -d "\n")' \
		'  jq -cn --arg payload "$payload" '\''{payload:$payload,payloadType:"application/vnd.in-toto+json",signatures:[{sig:"fixture"}]}'\''' \
		'else' \
		'  printf "[{\"critical\":{\"type\":\"https://sigstore.dev/cosign/sign/v1\",\"image\":{\"docker-manifest-digest\":\"%s\"}}}]\n" "$FIXTURE_NEW_DIGEST"' \
		'fi'
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
		'  https://api.github.com/repos/dexidp/dex/commits/master) printf "{\"sha\":\"%s\"}\n" "$FIXTURE_NEW_COMMIT" ;;' \
		'  *"$FIXTURE_NEW_COMMIT"*) cp "$FIXTURE_NEW_ARCHIVE" "$destination" ;;' \
		'  *) cp "$FIXTURE_OLD_ARCHIVE" "$destination" ;;' \
		'esac'
	write_executable "$bin/npm" \
		'#!/bin/sh' \
		'set -eu' \
		'printf "npm %s\n" "$*" >>"$UPDATE_TEST_LOG"' \
		'if [ "$*" = "run generate" ] && [ -n "${FIXTURE_GENERATE_DELETE:-}" ]; then' \
		'  rm -f -- "$FIXTURE_GENERATE_DELETE"' \
		'fi' \
		'if [ "$*" = "run generate" ]; then' \
		'  case "${FIXTURE_GIT_MUTATION:-}" in' \
		'    tag) git -C "$UPDATE_ROOT" tag update-lock-injected-mutation ;;' \
		'    detached-head)' \
		'      tree=$(git -C "$UPDATE_ROOT" rev-parse "HEAD^{tree}")' \
		'      new_head=$(printf "%s\n" mutation | git -C "$UPDATE_ROOT" commit-tree "$tree" -p HEAD)' \
		'      git -C "$UPDATE_ROOT" update-ref --no-deref HEAD "$new_head"' \
		'      ;;' \
		'    symbolic-head)' \
		'      git -C "$UPDATE_ROOT" update-ref refs/heads/update-lock-injected HEAD' \
		'      git -C "$UPDATE_ROOT" symbolic-ref HEAD refs/heads/update-lock-injected' \
		'      ;;' \
		'    remote-ref) git -C "$UPDATE_ROOT" update-ref refs/remotes/fixture/injected HEAD ;;' \
		'    remote-config) git -C "$UPDATE_ROOT" config --local remote.fixture.url https://mutated.invalid/dex.git ;;' \
		'  esac' \
		'fi'
}

prepare_repository() {
	root=$1
	current_header=$2
	locked_commit=${3:-$old_commit}
	locked_digest=${4:-$old_digest}
	locked_image=${5:-ghcr.io/dexidp/dex:master@$locked_digest}
	from_suffix=${6:-}
	old_archive_hash=$(digest "$(dirname "$root")/old.tar.gz")
	mkdir -p "$root/scripts" "$root/src" "$root/test" "$root/web" "$root/node_modules" "$root/.cache/sources"
	cat >"$root/versions.env" <<EOF
DEX_COMMIT=$locked_commit
DEX_IMAGE=$locked_image
DEX_SOURCE_URL=https://github.com/dexidp/dex/archive/$locked_commit.tar.gz
DEX_SOURCE_FILENAME=dex.tar.gz
DEX_SOURCE_SHA256=$old_archive_hash
DEX_BASE_X_MOD_VERSION=v0.37.0
DEX_X_MOD_VERSION=v0.40.0
DEX_BASE_API_GRPC_VERSION=v1.82.0
DEX_API_GRPC_VERSION=v1.82.1
EOF
	printf 'FROM %s%s\n' "$locked_image" "$from_suffix" >"$root/Dockerfile"
	printf '%s\n' "$current_header" >"$root/src/header.html"
	printf '%s\n' 'footer base' 'footer overlay' >"$root/src/footer.html"
	printf "upstream='%s'\n" "$locked_image" >"$root/test/image-overlay_test.sh"
	printf 'dex_commit=%s\n' "$locked_commit" >"$root/test/fetch-sources_test.sh"
	printf '%s\n' '#!/bin/sh' 'set -eu' 'printf "fetch-sources\n" >>"$UPDATE_TEST_LOG"' >"$root/scripts/fetch-sources.sh"
	printf '%s\n' '#!/bin/sh' 'set -eu' 'printf "entrypoint-test\n" >>"$UPDATE_TEST_LOG"' >"$root/test/entrypoint_test.sh"
	printf '%s\n' '#!/bin/sh' 'set -eu' 'printf "image-overlay-test\n" >>"$UPDATE_TEST_LOG"' >"$root/test/image-overlay_test.sh.gate"
	printf '%s\n' '#!/bin/sh' 'set -eu' 'printf "real-image-test\n" >>"$UPDATE_TEST_LOG"' >"$root/scripts/test-image.sh"
	chmod +x "$root/scripts/fetch-sources.sh" "$root/test/entrypoint_test.sh" \
		"$root/test/image-overlay_test.sh.gate" "$root/scripts/test-image.sh"
	printf '%s\n' '{"name":"fixture","scripts":{"test":"true"}}' >"$root/package.json"
	printf '%s\n' '{"lockfileVersion":3}' >"$root/package-lock.json"
	printf '%s\n' 'fixture manifest' >"$root/web/manifest.sha256"
	printf '%s\n' 'obsolete generated fixture' >"$root/web/obsolete.html"
	printf '%s\n' '.cache/' 'node_modules/' >"$root/.gitignore"
	git -C "$root" init -q
	git -C "$root" config user.name 'Update Lock Test'
	git -C "$root" config user.email update-lock@example.invalid
	git -C "$root" add .
	git -C "$root" commit -qm fixture
	git -C "$root" tag fixture-tag
	git -C "$root" remote add fixture https://example.invalid/dex.git
	printf '%s\n' stale >"$root/.cache/sources/stale"
}

git_metadata_snapshot() {
	root=$1
	{
		printf 'HEAD\t%s\n' "$(git -C "$root" rev-parse HEAD)"
		printf 'symbolic-HEAD\t%s\n' "$(git -C "$root" symbolic-ref -q HEAD || printf detached)"
		git -C "$root" for-each-ref --format='ref\t%(refname)\t%(objectname)'
		git -C "$root" config --local --get-regexp '^remote\.' 2>/dev/null || :
	} | LC_ALL=C sort
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
	FIXTURE_NEW_VERSION="$(cat "$case_dir/new-version")" \
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
	FIXTURE_NEW_VERSION="$(cat "$case_dir/new-version")" \
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
	[ -z "$(git -C "$case_dir/repo" status --porcelain --untracked-files=no)" ] ||
		fail 'failed update changed tracked files'
}

make_case() {
	name=$1
	case_dir=$tmp/$name
	mkdir -p "$case_dir"
	prepare_fake_commands "$case_dir/bin"
	: >"$case_dir/commands.log"
	printf '%s\n' "$new_commit" >"$case_dir/new-commit"
	printf '%s\n' "$new_digest" >"$case_dir/new-digest"
	printf '%s\n' "$new_version" >"$case_dir/new-version"
	printf '%s\n' "$case_dir"
}

case_dir=$(make_case revision-mismatch)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
expect_failure "$case_dir" 'OCI revision label does not match resolved Dex commit' \
	env FIXTURE_REVISION="$old_commit"

case_dir=$(make_case version-label-invalid)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
expect_failure "$case_dir" 'Dex image version label is missing or inconsistent' \
	env FIXTURE_VERSION=v2.46.0

case_dir=$(make_case master-version-label)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
run_update "$case_dir" env FIXTURE_VERSION=master
grep -Fx "DEX_IMAGE=ghcr.io/dexidp/dex:master@$new_digest" "$case_dir/repo/versions.env" >/dev/null ||
    fail 'master image was not pinned by digest'
grep -F "docker buildx imagetools inspect ghcr.io/dexidp/dex@$new_digest --format {{json .Image}}" "$case_dir/commands.log" >/dev/null ||
    fail 'image labels were not read from the resolved immutable digest'

grep -Fx DEX_X_MOD_VERSION=v0.40.0 "$case_dir/repo/versions.env" >/dev/null || fail 'x/mod security floor was downgraded'
grep -Fx DEX_API_GRPC_VERSION=v1.82.1 "$case_dir/repo/versions.env" >/dev/null || fail 'gRPC security floor was downgraded'

case_dir=$(make_case advanced-security-baselines)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
FIXTURE_SOURCE_X_MOD=v0.42.0 FIXTURE_SOURCE_GRPC=v1.84.0 make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
run_update "$case_dir" env
for expected in DEX_BASE_X_MOD_VERSION=v0.42.0 DEX_X_MOD_VERSION=v0.42.0 DEX_BASE_API_GRPC_VERSION=v1.84.0 DEX_API_GRPC_VERSION=v1.84.0; do
    grep -Fx "$expected" "$case_dir/repo/versions.env" >/dev/null || fail "missing $expected"
done

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

case_dir=$(make_case outside-report)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
printf '%s\n' 'outside sentinel' >"$case_dir/outside-report.md"
expect_failure "$case_dir" 'UPDATE_REPORT_FILE must use .cache/update-report.md inside the repository' \
	env UPDATE_REPORT_FILE="$case_dir/outside-report.md"
grep -Fx 'outside sentinel' "$case_dir/outside-report.md" >/dev/null ||
	fail 'outside report target was modified'

case_dir=$(make_case symlink-report)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
printf '%s\n' 'symlink sentinel' >"$case_dir/external-report.md"
ln -s "$case_dir/external-report.md" "$case_dir/repo/.cache/update-report.md"
expect_failure "$case_dir" 'update report must not be a symlink' env
[ -L "$case_dir/repo/.cache/update-report.md" ] || fail 'report symlink type changed'
grep -Fx 'symlink sentinel' "$case_dir/external-report.md" >/dev/null ||
	fail 'report symlink referent was modified'

case_dir=$(make_case symlink-report-parent)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay'
mv "$case_dir/repo/.cache" "$case_dir/external-cache"
printf '%s\n' 'parent sentinel' >"$case_dir/external-cache/sentinel"
ln -s "$case_dir/external-cache" "$case_dir/repo/.cache"
expect_failure "$case_dir" 'update report parent must not be a symlink' env
[ -L "$case_dir/repo/.cache" ] || fail 'report parent symlink type changed'
grep -Fx 'parent sentinel' "$case_dir/external-cache/sentinel" >/dev/null ||
	fail 'report parent symlink referent was modified'

for mutation in tag detached-head symbolic-head remote-ref remote-config; do
	case_dir=$(make_case "git-mutation-$mutation")
	make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
	make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
	prepare_repository "$case_dir/repo" 'header base
header overlay'
	git_metadata_snapshot "$case_dir/repo" >"$case_dir/git-before"
	if run_update "$case_dir" env FIXTURE_GIT_MUTATION="$mutation"; then
		fail "expected Git metadata mutation to fail preparation: $mutation"
	fi
	grep -F 'Git HEAD, refs, tags, or remotes changed during preparation' "$case_dir/stderr" >/dev/null || {
		sed -n '1,120p' "$case_dir/stderr" >&2
		fail "missing Git metadata mutation diagnostic: $mutation"
	}
	git_metadata_snapshot "$case_dir/repo" >"$case_dir/git-after"
	cmp -s "$case_dir/git-before" "$case_dir/git-after" ||
		fail "Git metadata mutation was not restored: $mutation"
	[ -z "$(git -C "$case_dir/repo" status --short)" ] ||
		fail "Git mutation failure changed tracked files: $mutation"
done

case_dir=$(make_case changed-update)
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
prepare_repository "$case_dir/repo" 'header base
header overlay' "$old_commit" "$old_digest" "ghcr.io/dexidp/dex:master@$old_digest" ' AS upstream'
git_metadata_snapshot "$case_dir/repo" >"$case_dir/git-before"
run_update "$case_dir" env FIXTURE_GENERATE_DELETE=web/obsolete.html
git_metadata_snapshot "$case_dir/repo" >"$case_dir/git-after"
cmp -s "$case_dir/git-before" "$case_dir/git-after" ||
	fail 'successful update mutated Git HEAD, refs, tags, or remotes'
grep -Fx "DEX_COMMIT=$new_commit" "$case_dir/repo/versions.env" >/dev/null
grep -Fx "DEX_IMAGE=ghcr.io/dexidp/dex:$new_version@$new_digest" "$case_dir/repo/versions.env" >/dev/null
grep -Fx "DEX_SOURCE_URL=https://github.com/dexidp/dex/archive/$new_commit.tar.gz" \
	"$case_dir/repo/versions.env" >/dev/null
grep -Fx "FROM ghcr.io/dexidp/dex:$new_version@$new_digest AS upstream" "$case_dir/repo/Dockerfile" >/dev/null
grep -Fx "dex_commit=$new_commit" "$case_dir/repo/test/fetch-sources_test.sh" >/dev/null
grep -Fx "upstream='ghcr.io/dexidp/dex:$new_version@$new_digest'" \
	"$case_dir/repo/test/image-overlay_test.sh" >/dev/null
[ ! -e "$case_dir/repo/web/obsolete.html" ] || fail 'staged generated deletion was not installed'
grep -Fx -e "- New commit: \`$new_commit\`" "$case_dir/repo/.cache/update-report.md" >/dev/null
grep -Fx -e "- New image: \`ghcr.io/dexidp/dex:$new_version@$new_digest\`" "$case_dir/repo/.cache/update-report.md" >/dev/null
grep -Fx -e "- New digest: \`$new_digest\`" "$case_dir/repo/.cache/update-report.md" >/dev/null
[ ! -e "$case_dir/repo/.cache/sources/stale" ] || fail 'changed update preserved stale source-cache content'

for checkpoint in after-files after-web after-cache after-report; do
	case_dir=$(make_case "install-rollback-$checkpoint")
	make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
	make_archive "$new_commit" "$case_dir/new.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
	prepare_repository "$case_dir/repo" 'header base
header overlay'
	printf '%s\n' 'prior report' >"$case_dir/repo/.cache/update-report.md"
	expect_failure "$case_dir" "injected install failure: $checkpoint" \
		env FIXTURE_GENERATE_DELETE=web/obsolete.html UPDATE_TEST_INSTALL_FAIL_AT="$checkpoint"
	[ -e "$case_dir/repo/web/obsolete.html" ] ||
		fail "rollback after $checkpoint did not restore generated deletion"
	[ -e "$case_dir/repo/.cache/sources/stale" ] ||
		fail "rollback after $checkpoint did not restore source cache"
	grep -Fx 'prior report' "$case_dir/repo/.cache/update-report.md" >/dev/null ||
		fail "rollback after $checkpoint did not restore prior report"
done

case_dir=$(make_case no-op)
printf '%s\n' "$old_commit" >"$case_dir/new-commit"
printf '%s\n' "$old_digest" >"$case_dir/new-digest"
make_archive "$old_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
cp "$case_dir/old.tar.gz" "$case_dir/new.tar.gz"
prepare_repository "$case_dir/repo" 'header base
header overlay' "$old_commit" "$old_digest" "ghcr.io/dexidp/dex:$new_version@$old_digest"
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
grep -F "cosign verify-attestation --certificate-identity https://github.com/dexidp/dex/.github/workflows/artifacts.yaml@refs/heads/master --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-github-workflow-repository dexidp/dex --certificate-github-workflow-ref refs/heads/master --certificate-github-workflow-sha $old_commit --type slsaprovenance1 --output json ghcr.io/dexidp/dex:$new_version@$old_digest" \
	"$case_dir/commands.log" >/dev/null || fail 'update-lock did not use credentialless Cosign provenance verification'
if grep -F 'gh ' "$case_dir/commands.log" >/dev/null; then
	fail 'update-lock used GitHub CLI credentials for public verification'
fi
grep -F 'WebAuthn script: unchanged' "$case_dir/repo/.cache/update-report.md" >/dev/null
grep -F 'Human screenshot review: required' "$case_dir/repo/.cache/update-report.md" >/dev/null
if grep -E '(gh pr|git push|git tag|docker push)' "$case_dir/commands.log" >/dev/null; then
	fail 'update-lock attempted a prohibited remote mutation'
fi

: >"$case_dir/commands.log"
run_lock_verification "$case_dir"
grep -F 'cosign verify' "$case_dir/commands.log" >/dev/null
grep -F 'cosign verify-attestation' "$case_dir/commands.log" >/dev/null ||
	fail 'lock-only verification skipped credentialless Cosign provenance'
if grep -E '(docker buildx build|curl |npm |fetch-sources|image-test|gh )' "$case_dir/commands.log" >/dev/null; then
	fail 'lock-only verification resolved or prepared an update'
fi

case_dir=$(make_case prerelease-lock-verification)
printf '%s\n' "$approved_prerelease_commit" >"$case_dir/new-commit"
printf '%s\n' "$approved_prerelease_digest" >"$case_dir/new-digest"
make_archive "$approved_prerelease_commit" "$case_dir/old.tar.gz" 'header base' 'footer base' 'const webauthn = "same";'
cp "$case_dir/old.tar.gz" "$case_dir/new.tar.gz"
approved_prerelease_ref=ghcr.io/dexidp/dex:$approved_prerelease_tag@$approved_prerelease_digest
prepare_repository "$case_dir/repo" 'header base
header overlay' "$approved_prerelease_commit" "$approved_prerelease_digest" "$approved_prerelease_ref"

: >"$case_dir/commands.log"
if ! run_lock_verification "$case_dir"; then
	sed -n '1,120p' "$case_dir/stderr" >&2
	fail 'approved prerelease lock-only verification failed'
fi
grep -F "$approved_prerelease_ref" "$case_dir/commands.log" >/dev/null ||
	fail 'prerelease lock verification did not inspect the exact approved reference'
grep -F 'cosign verify-attestation' "$case_dir/commands.log" >/dev/null ||
	fail 'prerelease lock verification skipped credentialless Cosign provenance'
if grep -E '(docker buildx build|curl |npm |fetch-sources|image-test|gh )' "$case_dir/commands.log" >/dev/null; then
	fail 'prerelease lock-only verification resolved or prepared an update'
fi

: >"$case_dir/commands.log"
if ! run_update "$case_dir" env; then
	sed -n '1,120p' "$case_dir/stderr" >&2
	fail 'approved prerelease update preparation failed'
fi
grep -F 'docker buildx imagetools inspect ghcr.io/dexidp/dex:master' "$case_dir/commands.log" >/dev/null ||
	fail 'prerelease update did not discover the next official master image'
grep -Fx "DEX_IMAGE=ghcr.io/dexidp/dex:$new_version@$approved_prerelease_digest" "$case_dir/repo/versions.env" >/dev/null ||
	fail 'prerelease update did not write the discovered immutable image version'
grep -Fx "FROM ghcr.io/dexidp/dex:$new_version@$approved_prerelease_digest" "$case_dir/repo/Dockerfile" >/dev/null ||
	fail 'prerelease update did not update the Dockerfile to the discovered image version'

update_workflow=$repo/.github/workflows/update-upstream.yml
ci_workflow=$repo/.github/workflows/ci.yml
verify_job=$tmp/update-verify-job.yml
validate_job=$tmp/update-validate-job.yml
arm64_job=$tmp/update-arm64-job.yml
publish_job=$tmp/update-publish-job.yml
verify_checkout=$tmp/update-verify-checkout.yml
validate_checkout=$tmp/update-validate-checkout.yml
publish_precheck=$tmp/update-publish-precheck.yml
sed -n '/^  verify:/,/^  validate:/p' "$update_workflow" >"$verify_job"
sed -n '/^  validate:/,/^  verify-arm64:/p' "$update_workflow" >"$validate_job"
sed -n '/^  verify-arm64:/,/^  publish:/p' "$update_workflow" >"$arm64_job"
sed -n '/^  publish:/,$p' "$update_workflow" >"$publish_job"
sed -n '/- name: Check out repository without persisted credentials/,/- name: Read locked tool versions/p' "$verify_job" >"$verify_checkout"
sed -n '/- name: Check out verified base without persisted credentials/,/- name: Download verified prepared update/p' "$validate_job" >"$validate_checkout"
sed -n '/- name: Pre-check immutable artifact binding/,/- name: Check out validated base without persisted credentials/p' "$publish_job" >"$publish_precheck"

grep -Fx 'permissions: {}' "$update_workflow" >/dev/null ||
	fail 'update workflow must deny permissions by default'
grep -F 'contents: read' "$verify_job" >/dev/null ||
	fail 'update verification job lacks read-only contents permission'
grep -F 'packages: read' "$verify_job" >/dev/null ||
	fail 'update verification job lacks read-only packages permission'
if grep -F ': write' "$verify_job" >/dev/null; then
	fail 'update verification job has write permission'
fi
if grep -F 'GH_TOKEN' "$verify_job" >/dev/null; then
	fail 'update verification job exposes GH_TOKEN to verification steps'
fi
grep -F 'token: ${{ github.token }}' "$verify_checkout" >/dev/null ||
	fail 'verifier checkout does not use the explicit read-only job token'
grep -F 'needs: verify' "$validate_job" >/dev/null ||
	fail 'artifact validator does not depend on verified preparation'
grep -F 'contents: read' "$validate_job" >/dev/null ||
	fail 'artifact validator lacks read-only contents permission'
if grep -E ': write|GH_TOKEN|gh auth setup-git|git push|gh pr create' "$validate_job" >/dev/null; then
	fail 'artifact validator has write authority or lifecycle commands'
fi
grep -F 'token: ${{ github.token }}' "$validate_checkout" >/dev/null ||
	fail 'read-only validator checkout does not use its explicit job token'
grep -F 'needs: [validate, verify-arm64]' "$publish_job" >/dev/null ||
	fail 'update publisher does not depend on read-only artifact validation'
grep -F "needs.verify-arm64.result == 'success'" "$publish_job" >/dev/null ||
    fail 'update publisher does not require a successful native arm64 build'
grep -F 'needs: [verify, validate]' "$arm64_job" >/dev/null &&
    grep -F 'runs-on: ubuntu-24.04-arm' "$arm64_job" >/dev/null &&
    grep -F 'contents: read' "$arm64_job" >/dev/null &&
    grep -F 'artifact-ids: ${{ needs.validate.outputs.artifact_id }}' "$arm64_job" >/dev/null &&
    grep -F 'ref: ${{ needs.verify.outputs.base_commit }}' "$arm64_job" >/dev/null &&
    grep -F 'EXPECTED_PATCH_SHA256' "$arm64_job" >/dev/null &&
    grep -F 'run: scripts/fetch-sources.sh' "$arm64_job" >/dev/null &&
    grep -F 'git apply --check' "$arm64_job" >/dev/null &&
    grep -F 'git apply --index' "$arm64_job" >/dev/null &&
    grep -F 'docker buildx build --platform linux/arm64 --load' "$arm64_job" >/dev/null ||
    fail 'native arm64 job is not bound to the validated base and artifact'
if grep -E ': write|GH_TOKEN|gh auth setup-git|git push|gh pr create' "$arm64_job" >/dev/null; then
    fail 'native arm64 job has write authority or lifecycle commands'
fi
grep -F 'contents: write' "$publish_job" >/dev/null ||
	fail 'update publisher lacks contents write permission'
grep -F 'pull-requests: write' "$publish_job" >/dev/null ||
	fail 'update publisher lacks pull-request write permission'

checkout_count=$(grep -c 'uses: actions/checkout@' "$update_workflow")
nonpersistent_checkout_count=$(grep -c 'persist-credentials: false' "$update_workflow")
[ "$checkout_count" -eq 4 ] || fail 'update workflow must check out once per isolated job'
[ "$nonpersistent_checkout_count" -eq "$checkout_count" ] ||
	fail 'every update checkout must disable persisted credentials'

grep -F 'uses: actions/download-artifact@' "$validate_job" >/dev/null ||
	fail 'read-only validator does not receive the prepared artifact'
grep -F 'artifact-ids:' "$validate_job" >/dev/null ||
	fail 'read-only validator does not download by immutable artifact ID'
grep -F 'prepared-update.patch' "$update_workflow" >/dev/null ||
	fail 'update workflow lacks a prepared patch artifact'
grep -F 'patch_sha256' "$update_workflow" >/dev/null ||
	fail 'prepared patch is not checksum-bound'
grep -F 'metadata_sha256' "$update_workflow" >/dev/null ||
	fail 'prepared artifact metadata is not checksum-bound'
grep -F 'EXPECTED_WORKFLOW_COMMIT' "$validate_job" >/dev/null ||
	fail 'artifact validator does not bind the verified workflow commit'
grep -F 'git apply --check' "$validate_job" >/dev/null ||
	fail 'artifact validator does not validate patch applicability'
grep -F 'git apply --index' "$validate_job" >/dev/null ||
	fail 'artifact validator does not stage the validated patch'
grep -F 'unexpected prepared path' "$validate_job" >/dev/null ||
	fail 'artifact validator lacks the prepared-path allowlist'
grep -F 'binding_sha256' "$validate_job" >/dev/null ||
	fail 'artifact validator does not emit a bound validation result'
grep -F 'Apply and recheck validated patch' "$publish_job" >/dev/null ||
	fail 'publisher does not recheck the applied patch'
grep -F 'Pre-check immutable artifact binding' "$publish_job" >/dev/null ||
	fail 'publisher does not pre-check the immutable artifact binding'
grep -F 'ref: ${{ needs.validate.outputs.base_commit }}' "$publish_job" >/dev/null ||
	fail 'publisher checkout is not bound to the read-only validation result'
grep -F 'artifact-ids: ${{ needs.validate.outputs.artifact_id }}' "$publish_job" >/dev/null ||
	fail 'publisher download is not bound to the validated artifact ID'

validation_job_line=$(grep -n -x '  validate:' "$update_workflow" | cut -d: -f1)
publish_job_line=$(grep -n -x '  publish:' "$update_workflow" | cut -d: -f1)
validation_line=$(grep -n -F -- '- name: Validate prepared update' "$validate_job" | cut -d: -f1)
download_line=$(grep -n -F -- '- name: Download validated prepared update' "$publish_job" | cut -d: -f1)
precheck_line=$(grep -n -F -- '- name: Pre-check immutable artifact binding' "$publish_job" | cut -d: -f1)
checkout_line=$(grep -n -F -- '- name: Check out validated base without persisted credentials' "$publish_job" | cut -d: -f1)
recheck_line=$(grep -n -F -- '- name: Apply and recheck validated patch' "$publish_job" | cut -d: -f1)
credential_line=$(grep -n -F -- '- name: Configure write credentials' "$publish_job" | cut -d: -f1)
branch_line=$(grep -n -F -- '- name: Create and push update branch' "$publish_job" | cut -d: -f1)
[ -n "$validation_job_line" ] && [ -n "$publish_job_line" ] &&
	[ "$validation_job_line" -lt "$publish_job_line" ] ||
	fail 'write-permission job exists before read-only artifact validation'
[ -n "$validation_line" ] && [ -n "$download_line" ] && [ -n "$precheck_line" ] &&
	[ -n "$checkout_line" ] && [ -n "$recheck_line" ] && [ -n "$credential_line" ] &&
	[ -n "$branch_line" ] ||
	fail 'update publisher lifecycle steps are incomplete'
[ "$download_line" -lt "$precheck_line" ] && [ "$precheck_line" -lt "$checkout_line" ] &&
	[ "$checkout_line" -lt "$recheck_line" ] && [ "$recheck_line" -lt "$credential_line" ] &&
	[ "$credential_line" -lt "$branch_line" ] ||
	fail 'publisher checkout, patch application, or credentials precede required binding gates'
grep -F 'EXPECTED_ARTIFACT_ID' "$publish_precheck" >/dev/null &&
	grep -F 'EXPECTED_BASE_COMMIT' "$publish_precheck" >/dev/null &&
	grep -F 'EXPECTED_BINDING_SHA256' "$publish_precheck" >/dev/null &&
	grep -F 'sha256sum "$metadata"' "$publish_precheck" >/dev/null &&
	grep -F 'sha256sum "$patch"' "$publish_precheck" >/dev/null &&
	grep -F 'sha256sum "$report"' "$publish_precheck" >/dev/null &&
	grep -F 'sha256sum "$manifest"' "$publish_precheck" >/dev/null &&
	grep -F 'git apply --numstat -z "$patch" > "$numstat"' "$publish_precheck" >/dev/null &&
	grep -F 'unexpected prepared path before checkout' "$publish_precheck" >/dev/null &&
	grep -F -- '- New commit:' "$publish_precheck" >/dev/null &&
	grep -F -- '- New digest:' "$publish_precheck" >/dev/null &&
	grep -F -- '- Generated manifest digest:' "$publish_precheck" >/dev/null ||
	fail 'publisher pre-check does not fully bind artifact, base, hashes, paths, and report'
if grep -E '(source|eval|bash|sh)[[:space:]].*(metadata|prepared-update\.patch|update-report\.md|manifest\.sha256)' "$publish_precheck" >/dev/null; then
	fail 'publisher pre-check sources or executes artifact content'
fi

grep -F 'contents: read' "$ci_workflow" >/dev/null || fail 'CI lost read-only contents permission'
grep -F 'packages: read' "$ci_workflow" >/dev/null || fail 'CI lost read-only packages permission'
if grep -F ': write' "$ci_workflow" >/dev/null; then
	fail 'CI gained write permission'
fi
if grep -F 'GH_TOKEN' "$ci_workflow" >/dev/null; then
	fail 'CI verification exposes GH_TOKEN to verification steps'
fi

for workflow in "$ci_workflow" "$update_workflow"; do
	uses_count=$(grep -c '^[[:space:]]*uses:' "$workflow")
	pinned_count=$(awk '/^[[:space:]]*uses:/ && /@[0-9a-f]{40}[[:space:]]+# v[0-9]/ { count++ } END { print count + 0 }' "$workflow")
	[ "$uses_count" -eq "$pinned_count" ] || fail "workflow action is not immutably pinned: ${workflow#$repo/}"
done

printf '%s\n' 'update-lock fixtures: PASS'
