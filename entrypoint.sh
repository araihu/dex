#!/bin/sh
set -eu

upstream=${UPSTREAM_ENTRYPOINT:-/usr/local/bin/docker-entrypoint}

if [ "${DEX_FRONTEND_DIR+x}" = x ] && [ -z "$DEX_FRONTEND_DIR" ]; then
	exec "$upstream" "$@"
fi

theme=${ARAIHU_DEX_THEME:-araihu}
case "$theme" in
	90s|araihu|arctic|christmas|dracula|goshtoso|halloween|high-contrast|industrial|minimal|modern|neo-brutalism|news|pastel|prototype|zombie)
		;;
	*)
		printf '%s\n' 'entrypoint: invalid ARAIHU_DEX_THEME' >&2
		exit 1
		;;
esac

printf 'window.__araihuDexDefaultTheme = "%s";\n' "$theme" \
	>"${THEME_DEFAULT_FILE:-/srv/dex/web/static/theme-default.js}"

exec "$upstream" "$@"
