#!/bin/sh
set -eu

die() {
	printf '%s\n' "test-image: $*" >&2
	exit 1
}

[ "$#" -ge 1 ] || die 'usage: scripts/test-image.sh IMAGE [playwright arguments...]'
image=$1
shift

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture=$repo/test/fixtures/dex.yaml
proxy=$repo/test/fixtures/csp-proxy.mjs

command -v docker >/dev/null 2>&1 || die 'docker is required'
command -v node >/dev/null 2>&1 || die 'node is required'
command -v curl >/dev/null 2>&1 || die 'curl is required'
[ -f "$fixture" ] || die "fixture not found: $fixture"
[ -f "$proxy" ] || die "proxy not found: $proxy"
docker image inspect "$image" >/dev/null 2>&1 || die "image not found: $image"

state=$(mktemp -d "${TMPDIR:-/tmp}/araihu-dex-test.XXXXXX")
chmod 0777 "$state"
container="araihu-dex-test-$$"
proxy_pid=

cleanup() {
	status=$?
	trap - EXIT HUP INT TERM
	if [ -n "$proxy_pid" ]; then
		kill "$proxy_pid" 2>/dev/null || true
		wait "$proxy_pid" 2>/dev/null || true
	fi
	docker rm -f "$container" >/dev/null 2>&1 || true
	rm -rf "$state"
	exit "$status"
}
trap cleanup EXIT HUP INT TERM

proxy_port=$(node -e 'const net=require("node:net");const server=net.createServer();server.listen(0,"127.0.0.1",()=>{process.stdout.write(String(server.address().port));server.close();});')
origin="http://localhost:$proxy_port"

docker run -d --name "$container" \
	-p 127.0.0.1::5556 \
	--mount "type=bind,src=$fixture,dst=/etc/dex/test.yaml,readonly" \
	--mount "type=bind,src=$state,dst=/var/dex-test" \
	-e DEX_SESSIONS_ENABLED=true \
	-e "DEX_TEST_ISSUER=$origin" \
	-e "DEX_TEST_ORIGIN=$origin" \
	-e "DEX_TEST_REDIRECT_URI=$origin/client/callback" \
	-e DEX_TEST_DB=/var/dex-test/dex.db \
	"$image" dex serve /etc/dex/test.yaml >"$state/container-id"

mapping=$(docker port "$container" 5556/tcp)
upstream_port=${mapping##*:}
[ -n "$upstream_port" ] || die 'docker did not publish Dex port'

DEX_TEST_UPSTREAM="http://127.0.0.1:$upstream_port" \
	DEX_TEST_PROXY_PORT=$proxy_port \
	node "$proxy" >"$state/proxy.log" 2>&1 &
proxy_pid=$!

ready=false
attempt=0
while [ "$attempt" -lt 100 ]; do
	if curl -fsS "$origin/healthz" >/dev/null 2>&1; then
		ready=true
		break
	fi
	docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -qx true || break
	kill -0 "$proxy_pid" 2>/dev/null || break
	attempt=$((attempt + 1))
	sleep 0.1
done

if [ "$ready" != true ]; then
	docker logs "$container" >&2 || true
	sed -n '1,120p' "$state/proxy.log" >&2 || true
	die 'Dex did not become healthy'
fi

DEX_TEST_BASE_URL=$origin \
	DEX_TEST_DB="$state/dex.db" \
	DEX_TEST_CONTAINER="$container" \
	env -u NO_COLOR npx playwright test "$@"
