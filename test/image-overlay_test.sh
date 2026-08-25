#!/bin/sh
set -eu

image=${1:?usage: image-overlay_test.sh IMAGE}
upstream='ghcr.io/dexidp/dex:master@sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b'
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

upstream_container=$(docker create --entrypoint /bin/true "$upstream")
derived_container=$(docker create --entrypoint /bin/true "$image")
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
		./usr/share/licenses/araihu-dex/assets-NOTICE|\
		./usr/share/licenses/araihu-dex/Apache-2.0.txt|\
		./usr/share/licenses/araihu-dex/heroicons-MIT.txt|\
		./srv/dex/web/static/appearance.js|\
		./srv/dex/web/static/araihu-logo.svg|\
		./srv/dex/web/static/araihu-styles.css|\
		./srv/dex/web/static/favicon-32.png|\
		./srv/dex/web/static/favicon.svg|\
		./srv/dex/web/static/icons.svg|\
		./srv/dex/web/static/theme-default.js)
			;;
		*) fail "unapproved path added: $path" ;;
	esac
done <"$tmp/added.paths"

(cd "$tmp/upstream" && find . -type f -print | LC_ALL=C sort) | while IFS= read -r path; do
	[ -f "$tmp/derived/${path#./}" ] || continue
	if ! cmp -s "$tmp/upstream/${path#./}" "$tmp/derived/${path#./}"; then
		case "$path" in
			./srv/dex/web/templates/header.html|./srv/dex/web/templates/footer.html) ;;
			*) fail "unapproved upstream file changed: $path" ;;
		esac
	fi
done

for template in approval device device_success error home login logout oob password totp_verify webauthn_verify; do
	cmp "$tmp/upstream/srv/dex/web/templates/$template.html" \
		"$tmp/derived/srv/dex/web/templates/$template.html" ||
		fail "flow template changed: $template.html"
done

for path in \
	srv/dex/web/templates/header.html \
	srv/dex/web/templates/footer.html \
	srv/dex/web/static/appearance.js \
	srv/dex/web/static/araihu-logo.svg \
	srv/dex/web/static/araihu-styles.css \
	srv/dex/web/static/favicon-32.png \
	srv/dex/web/static/favicon.svg \
	srv/dex/web/static/icons.svg \
	srv/dex/web/static/theme-default.js \
	usr/local/bin/araihu-dex-entrypoint; do
	[ -f "$tmp/derived/$path" ] || fail "required overlay file missing: /$path"
done

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

printf '%s\n' 'image overlay tests passed'
