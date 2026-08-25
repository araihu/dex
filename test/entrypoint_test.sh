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
	printf '%s\n' sentinel >"$tmp/theme-default.js"
}

assert_upstream_called() {
	[ -f "$tmp/argv" ] || fail 'upstream entrypoint was not called'
	[ "$(cat "$tmp/argv")" = serve ] || fail 'upstream arguments changed'
}

assert_theme() {
	expected=$1
	[ "$(cat "$tmp/theme-default.js")" = "window.__araihuDexDefaultTheme = \"$expected\";" ] ||
		fail "wrong generated default theme for $expected"
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
	[ "$(cat "$tmp/theme-default.js")" = sentinel ] || fail 'invalid theme changed output'
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

printf '%s\n' 'entrypoint tests passed'
