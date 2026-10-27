#!/bin/sh
set -eu

image=${1:?usage: image-overlay_test.sh IMAGE}
upstream='ghcr.io/dexidp/dex:master@sha256:3cea00341c073adcf45b6f8ae9d3c26e5e1201316e3a5793c9129d8373f7bee6'
tmp=$(mktemp -d)
upstream_container=
derived_container=

cleanup() {
	[ -z "$upstream_container" ] || docker rm -f "$upstream_container" >/dev/null 2>&1 || true
	[ -z "$derived_container" ] || docker rm -f "$derived_container" >/dev/null 2>&1 || true
	rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

fail() {
	printf '%s\n' "image-overlay_test: $*" >&2
	exit 1
}

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
dex_x_mod_version=$(awk -F= '
    $1 == "DEX_X_MOD_VERSION" { value = $2; count++ }
    END { if (count != 1 || value == "") exit 1; print value }
' "$repo/versions.env") || fail 'DEX_X_MOD_VERSION must occur exactly once in the lock'

arch=$(docker image inspect "$image" --format '{{.Architecture}}')
case "$arch" in
	amd64|arm64) ;;
	*) fail "unsupported image architecture: $arch" ;;
esac
platform="linux/$arch"

upstream_digest=$(
	docker buildx imagetools inspect "$upstream" --format '{{json .Manifest}}' |
		jq -er --arg architecture "$arch" '
			[.manifests[] | select(
				.platform.os == "linux" and
				.platform.architecture == $architecture
			)] |
			if length == 1 then .[0].digest
			else error("upstream platform manifest count mismatch")
			end
		'
) || fail "cannot resolve upstream $platform manifest"
printf '%s\n' "$upstream_digest" | grep -Eq '^sha256:[0-9a-f]{64}$' ||
	fail "invalid upstream $platform manifest digest"
upstream_platform=${upstream%@*}@$upstream_digest

upstream_container=$(docker create --platform "$platform" --entrypoint /bin/true "$upstream_platform")
derived_container=$(docker create --platform "$platform" --entrypoint /bin/true "$image")
mkdir "$tmp/upstream" "$tmp/derived"
docker export "$upstream_container" | tar -xf - -C "$tmp/upstream"
docker export "$derived_container" | tar -xf - -C "$tmp/derived"

(cd "$tmp/upstream" && find . -mindepth 1 -print | LC_ALL=C sort) >"$tmp/upstream.paths"
(cd "$tmp/derived" && find . -mindepth 1 -print | LC_ALL=C sort) >"$tmp/derived.paths"
comm -23 "$tmp/upstream.paths" "$tmp/derived.paths" >"$tmp/removed.paths"
[ ! -s "$tmp/removed.paths" ] || fail "derived image removed upstream paths: $(head -1 "$tmp/removed.paths")"

comm -13 "$tmp/upstream.paths" "$tmp/derived.paths" >"$tmp/added.paths"
while IFS= read -r path; do
	case "$path" in
		./usr/local/bin/araihu-dex-entrypoint|\
		./usr/share/licenses|\
		./usr/share/licenses/araihu-dex|\
		./usr/share/licenses/araihu-dex/LICENSE|\
		./usr/share/licenses/araihu-dex/NOTICE|\
		./usr/share/licenses/araihu-dex/Lato-OFL-1.1.txt|\
		./usr/share/licenses/araihu-dex/musl-COPYRIGHT.txt|\
		./usr/share/licenses/araihu-dex/go-BSD-3-Clause.txt|\
		./usr/share/licenses/araihu-dex/go-module-licenses.sha256|\
		./usr/share/licenses/araihu-dex/go-modules|\
		./usr/share/licenses/araihu-dex/go-modules/*|\
		./usr/share/licenses/araihu-dex/gomplate-MIT.txt|\
		./usr/share/licenses/araihu-dex/assets-NOTICE|\
		./usr/share/licenses/araihu-dex/Apache-2.0.txt|\
		./usr/share/licenses/araihu-dex/heroicons-MIT.txt|\
		./srv/dex/web/static/appearance.js|\
		./srv/dex/web/static/araihu-lato-latin-400.woff2|\
		./srv/dex/web/static/araihu-lato-latin-700.woff2|\
		./srv/dex/web/static/araihu-logo.svg|\
		./srv/dex/web/static/araihu-styles.css|\
		./srv/dex/web/static/favicon-32.png|\
		./srv/dex/web/static/favicon.svg|\
		./srv/dex/web/static/icons.svg|\
		./srv/dex/web/static/theme-default.js|\
		./srv/dex/web/static/theme-default.template.js)
			;;
		*) fail "unapproved path added: $path" ;;
	esac
done <"$tmp/added.paths"

(cd "$tmp/upstream" && find . -type f -print | LC_ALL=C sort) | while IFS= read -r path; do
	[ -f "$tmp/derived/${path#./}" ] || continue
	if ! cmp -s "$tmp/upstream/${path#./}" "$tmp/derived/${path#./}"; then
		case "$path" in
			./srv/dex/web/templates/header.html|\
			./srv/dex/web/templates/footer.html|\
			./usr/local/bin/dex|\
			./usr/local/bin/docker-entrypoint|\
			./usr/local/bin/gomplate|\
			./usr/local/src/dex/go.mod|\
			./usr/local/src/dex/go.sum|\
			./usr/local/src/dex/api/v2/go.mod|\
			./usr/local/src/dex/api/v2/go.sum) ;;
			*) fail "unapproved upstream file changed: $path" ;;
		esac
	fi
done

assert_go_build() {
	binary=$1
	module=$2
	version=$3
	build_info=$(go version -m "$tmp/derived/usr/local/bin/$binary") ||
		fail "$binary does not expose Go build information"
	printf '%s\n' "$build_info" | grep -F ': go1.27.3' >/dev/null ||
		fail "$binary was not compiled with Go 1.27.3"
	if [ -n "$module" ]; then
		printf '%s\n' "$build_info" |
			awk -F '\t' -v module="$module" -v version="$version" \
				'$2 == "dep" && $3 == module && $4 == version { found = 1 } END { exit !found }' ||
			fail "$binary does not contain $module $version"
	fi
}

assert_go_build dex golang.org/x/mod "$dex_x_mod_version"
assert_go_build docker-entrypoint '' ''
assert_go_build gomplate github.com/go-git/go-git/v5 v5.19.2
gomplate_info=$(go version -m "$tmp/derived/usr/local/bin/gomplate")
printf '%s\n' "$gomplate_info" |
	awk -F '\t' '$2 == "dep" && $3 == "google.golang.org/grpc" && $4 == "v1.82.1" { found = 1 } END { exit !found }' ||
	fail 'gomplate does not contain google.golang.org/grpc v1.82.1'
printf '%s\n' "$gomplate_info" |
	awk -F '\t' '$2 == "dep" && $3 == "go.opentelemetry.io/otel" && $4 == "v1.44.0" { found = 1 } END { exit !found }' ||
	fail 'gomplate does not contain go.opentelemetry.io/otel v1.44.0'

for template in approval device device_success error home login logout oob password totp_verify webauthn_verify; do
	cmp "$tmp/upstream/srv/dex/web/templates/$template.html" \
		"$tmp/derived/srv/dex/web/templates/$template.html" ||
		fail "flow template changed: $template.html"
done

for path in \
	srv/dex/web/templates/header.html \
	srv/dex/web/templates/footer.html \
	srv/dex/web/static/appearance.js \
	srv/dex/web/static/araihu-lato-latin-400.woff2 \
	srv/dex/web/static/araihu-lato-latin-700.woff2 \
	srv/dex/web/static/araihu-logo.svg \
	srv/dex/web/static/araihu-styles.css \
	srv/dex/web/static/favicon-32.png \
	srv/dex/web/static/favicon.svg \
	srv/dex/web/static/icons.svg \
	srv/dex/web/static/theme-default.js \
	srv/dex/web/static/theme-default.template.js \
	usr/local/bin/araihu-dex-entrypoint; do
	[ -f "$tmp/derived/$path" ] || fail "required overlay file missing: /$path"
done
[ -f "$tmp/derived/usr/share/licenses/araihu-dex/gomplate-MIT.txt" ] ||
	fail 'Gomplate license is missing'
[ -f "$tmp/derived/usr/share/licenses/araihu-dex/go-BSD-3-Clause.txt" ] ||
	fail 'Go license is missing'
[ -f "$tmp/derived/usr/share/licenses/araihu-dex/musl-COPYRIGHT.txt" ] ||
	fail 'musl license is missing'
[ -s "$tmp/derived/usr/share/licenses/araihu-dex/go-module-licenses.sha256" ] ||
	fail 'Go module license inventory is missing'

[ "$(docker image inspect "$image" --format '{{.Config.User}}')" = '1001:1001' ] ||
	fail 'derived image user is not 1001:1001'
[ "$(docker image inspect "$image" --format '{{json .Config.Entrypoint}}')" = '["/usr/local/bin/araihu-dex-entrypoint"]' ] ||
	fail 'derived image entrypoint changed'
[ "$(docker image inspect "$image" --format '{{json .Config.Cmd}}')" = '["dex","serve","/etc/dex/config.docker.yaml"]' ] ||
	fail 'upstream CMD was not preserved'
frontend_env=$(docker image inspect "$image" --format '{{range .Config.Env}}{{println .}}{{end}}' |
	sed -n '/^DEX_FRONTEND_DIR=/p')
[ "$frontend_env" = 'DEX_FRONTEND_DIR=/srv/dex/web' ] ||
	fail 'DEX_FRONTEND_DIR image contract changed'
docker run --rm --entrypoint /bin/sh "$image" -c \
	'test "$(stat -c "%u:%g" /srv/dex/web/static/theme-default.js)" = 1001:1001 && test -w /srv/dex/web/static/theme-default.js && test ! -w /srv/dex/web/static' ||
	fail 'runtime default file ownership or write boundary changed'
docker run --rm --entrypoint /bin/sh "$image" -c \
	'test "$(stat -c "%u:%g" /srv/dex/web/static/theme-default.template.js)" = 0:0 && test ! -w /srv/dex/web/static/theme-default.template.js' ||
	fail 'immutable default template ownership or write boundary changed'

printf '%s\n' 'image overlay tests passed'
