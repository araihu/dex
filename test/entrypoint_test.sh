#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repo"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

printf '%s\n' \
	'#!/bin/sh' \
	'set -eu' \
	'printf "%s\n" "$@" >"$ARGV_FILE"' >"$tmp/upstream"
chmod +x "$tmp/upstream"

fail() {
	printf '%s\n' "entrypoint_test: $*" >&2
	exit 1
}

reset_case() {
	rm -f "$tmp/argv" "$tmp/error"
	printf '%s\n' \
		'window.__araihuDexDefaultTheme = "__ARAIHU_DEX_DEFAULT_THEME__";' \
		'window.__araihuDexThemeKeys = ["araihu"];' >"$tmp/theme-default.js"
}

assert_upstream_called() {
	[ -f "$tmp/argv" ] || fail 'upstream entrypoint was not called'
	[ "$(cat "$tmp/argv")" = serve ] || fail 'upstream arguments changed'
}

assert_theme() {
	expected=$1
	grep -Fqx "window.__araihuDexDefaultTheme = \"$expected\";" "$tmp/theme-default.js" ||
		fail "wrong generated default theme for $expected"
	grep -Fqx 'window.__araihuDexThemeKeys = ["araihu"];' "$tmp/theme-default.js" ||
		fail 'theme bootstrap body was not preserved'
	assert_upstream_called
}

reset_case
DEX_FRONTEND_DIR='' ARAIHU_DEX_THEME=' invalid ' \
	THEME_DEFAULT_FILE="$tmp/missing/theme-default.js" \
	ARGV_FILE="$tmp/argv" UPSTREAM_ENTRYPOINT="$tmp/upstream" \
	./entrypoint.sh serve
assert_upstream_called

reset_case
(
	unset ARAIHU_DEX_THEME DEX_FRONTEND_DIR
	THEME_DEFAULT_FILE="$tmp/theme-default.js" ARGV_FILE="$tmp/argv" \
		UPSTREAM_ENTRYPOINT="$tmp/upstream" ./entrypoint.sh serve
)
assert_theme araihu
first_render=$(cksum "$tmp/theme-default.js")
ARAIHU_DEX_THEME=araihu THEME_DEFAULT_FILE="$tmp/theme-default.js" \
	ARGV_FILE="$tmp/argv" UPSTREAM_ENTRYPOINT="$tmp/upstream" \
	./entrypoint.sh serve
assert_theme araihu
[ "$(cksum "$tmp/theme-default.js")" = "$first_render" ] ||
	fail 'second entrypoint start changed the rendered default theme'

reset_case
ARAIHU_DEX_THEME='' THEME_DEFAULT_FILE="$tmp/theme-default.js" \
	ARGV_FILE="$tmp/argv" UPSTREAM_ENTRYPOINT="$tmp/upstream" \
	./entrypoint.sh serve
assert_theme araihu

reset_case
ARAIHU_DEX_THEME=araihu THEME_DEFAULT_FILE="$tmp/theme-default.js" \
	ARGV_FILE="$tmp/argv" UPSTREAM_ENTRYPOINT="$tmp/upstream" \
	./entrypoint.sh serve
assert_theme araihu

while IFS="$(printf '\t')" read -r key label; do
	[ -n "$key" ] || continue
	reset_case
	ARAIHU_DEX_THEME=$key THEME_DEFAULT_FILE="$tmp/theme-default.js" \
		ARGV_FILE="$tmp/argv" UPSTREAM_ENTRYPOINT="$tmp/upstream" \
		./entrypoint.sh serve
	assert_theme "$key"
done <web/static/theme-allowlist.txt

assert_invalid() {
	value=$1
	reset_case
	if ARAIHU_DEX_THEME=$value THEME_DEFAULT_FILE="$tmp/theme-default.js" \
		ARGV_FILE="$tmp/argv" UPSTREAM_ENTRYPOINT="$tmp/upstream" \
		./entrypoint.sh serve >"$tmp/stdout" 2>"$tmp/error"; then
		fail 'invalid theme was accepted'
	fi
	[ ! -e "$tmp/argv" ] || fail 'upstream started for invalid theme'
	grep -Fq '__ARAIHU_DEX_DEFAULT_THEME__' "$tmp/theme-default.js" || fail 'invalid theme changed output'
	[ "$(cat "$tmp/error")" = 'entrypoint: invalid ARAIHU_DEX_THEME' ] ||
		fail 'invalid theme diagnostic leaked or changed'
}

assert_invalid unknown
assert_invalid ' araihu '
assert_invalid ARAIHU

reset_case
if ARAIHU_DEX_THEME=araihu THEME_DEFAULT_FILE="$tmp" \
	ARGV_FILE="$tmp/argv" UPSTREAM_ENTRYPOINT="$tmp/upstream" \
	./entrypoint.sh serve >"$tmp/stdout" 2>"$tmp/error"; then
	fail 'failed output write was accepted'
fi
[ ! -e "$tmp/argv" ] || fail 'upstream started after failed output write'

reset_case
printf '%s\n' sentinel >"$tmp/theme-without-marker.js"
if ARAIHU_DEX_THEME=araihu THEME_DEFAULT_FILE="$tmp/theme-without-marker.js" \
	ARGV_FILE="$tmp/argv" UPSTREAM_ENTRYPOINT="$tmp/upstream" \
	./entrypoint.sh serve >"$tmp/stdout" 2>"$tmp/error"; then
	fail 'missing template marker was accepted'
fi
[ ! -e "$tmp/argv" ] || fail 'upstream started after missing template marker'
[ "$(cat "$tmp/error")" = 'entrypoint: default theme template marker missing' ] ||
	fail 'missing marker diagnostic changed'

printf '%s\n' 'entrypoint tests passed'
