#!/bin/sh
set -eu

upstream=${UPSTREAM_ENTRYPOINT:-/usr/local/bin/docker-entrypoint}

if [ "${DEX_FRONTEND_DIR+x}" = x ] && [ -z "$DEX_FRONTEND_DIR" ]; then
	exec "$upstream" "$@"
fi

theme=${ARAIHU_DEX_THEME:-araihu}
is_valid_theme() {
	case "$1" in
		90s|araihu|arctic|christmas|dracula|goshtoso|halloween|high-contrast|industrial|minimal|modern|neo-brutalism|news|pastel|prototype|zombie)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

if ! is_valid_theme "$theme"; then
	printf '%s\n' 'entrypoint: invalid ARAIHU_DEX_THEME' >&2
	exit 1
fi

theme_file=${THEME_DEFAULT_FILE:-/srv/dex/web/static/theme-default.js}
template_file=${THEME_TEMPLATE_FILE:-/srv/dex/web/static/theme-default.template.js}
[ "$theme_file" != "$template_file" ] || {
	printf '%s\n' 'entrypoint: theme template and output must differ' >&2
	exit 1
}
template=$(cat "$template_file")
marker_line='window.__araihuDexDefaultTheme = "__ARAIHU_DEX_DEFAULT_THEME__";'
case "$template" in
	*"$marker_line"*)
		printf '%s\n' "$template" | sed "s/__ARAIHU_DEX_DEFAULT_THEME__/$theme/g" >"$theme_file"
		;;
	*)
		printf '%s\n' 'entrypoint: default theme template marker missing' >&2
		exit 1
		;;
esac

exec "$upstream" "$@"
