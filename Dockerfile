FROM ghcr.io/dexidp/dex:v2.46.0-20260806171424-ab64ed77@sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b AS upstream

FROM golang:1.27.0-alpine3.24@sha256:4c9fe60190a2a3350ddc51de80d0224b8a6698d12bdfc999fee45ea9d6c46dbc AS builder

RUN apk add --no-cache build-base ca-certificates

COPY .cache/sources/downloads/dex.tar.gz /tmp/dex.tar.gz
COPY versions.env /tmp/versions.env
RUN . /tmp/versions.env \
    && echo "$DEX_SOURCE_SHA256  /tmp/dex.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/local/src/dex \
    && tar -xzf /tmp/dex.tar.gz --strip-components=1 -C /usr/local/src/dex

COPY api/v2 /tmp/araihu-source-overlay/api/v2
COPY dex/server/apiserver/passwords.go /tmp/araihu-source-overlay/dex/server/apiserver/passwords.go
COPY scripts/prepare-dex-source.sh /tmp/araihu-source-overlay/scripts/prepare-dex-source.sh
RUN /tmp/araihu-source-overlay/scripts/prepare-dex-source.sh /usr/local/src/dex

WORKDIR /usr/local/src/dex
ENV GOTOOLCHAIN=local
RUN . /tmp/versions.env \
    && test "$(go env GOVERSION)" = go1.27.0 \
    && GOWORK=off go get "golang.org/x/mod@$DEX_X_MOD_VERSION" \
    && GOWORK=off go mod tidy \
    && cd api/v2 \
    && GOWORK=off go get "google.golang.org/grpc@$DEX_API_GRPC_VERSION" \
    && GOWORK=off go mod tidy
RUN . /tmp/versions.env \
    && dex_version=${DEX_IMAGE#*:} \
    && dex_version=${dex_version%@*} \
    && dex_version=$dex_version+araihu.password-profile.v1 \
    && CGO_ENABLED=1 GOFLAGS=-trimpath GOWORK=off go build \
      -ldflags "-w -X main.version=$dex_version -extldflags '-static'" \
      -o /go/bin/dex ./cmd/dex \
    && CGO_ENABLED=1 GOFLAGS=-trimpath GOWORK=off go build \
      -ldflags "-w -X main.version=$dex_version -extldflags '-static'" \
      -o /go/bin/docker-entrypoint ./cmd/docker-entrypoint

ADD --checksum=sha256:47cf3c43ef29320c4817e9bbb06581b14f1476b7a7a3ba1c31e547bb62afbd83 \
    https://github.com/hairyhenderson/gomplate/archive/117c916d306b2239081656622f00b802c82c16a0.tar.gz /tmp/gomplate.tar.gz
RUN mkdir -p /usr/local/src/gomplate \
    && tar -xzf /tmp/gomplate.tar.gz --strip-components=1 -C /usr/local/src/gomplate

WORKDIR /usr/local/src/gomplate
RUN GOWORK=off go get \
      github.com/go-git/go-git/v5@v5.19.2 \
      google.golang.org/grpc@v1.82.1 \
      go.opentelemetry.io/otel@v1.44.0 \
      go.opentelemetry.io/otel/metric@v1.44.0 \
      go.opentelemetry.io/otel/sdk@v1.44.0 \
      go.opentelemetry.io/otel/sdk/metric@v1.44.0 \
      go.opentelemetry.io/otel/trace@v1.44.0 \
    && GOWORK=off go mod tidy
RUN CGO_ENABLED=0 GOWORK=off go build -buildvcs=false -trimpath \
    -ldflags '-w -s -X github.com/hairyhenderson/gomplate/v5/version.GitCommit=117c916d306b2239081656622f00b802c82c16a0 -X github.com/hairyhenderson/gomplate/v5/version.Version=v5.2.0' \
    -o /go/bin/gomplate ./cmd/gomplate
RUN mkdir -p /tmp/go-licenses/go-modules \
    && cp /usr/local/go/LICENSE /tmp/go-licenses/go-BSD-3-Clause.txt \
    && cd /go/pkg/mod \
    && find . -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) \
      | LC_ALL=C sort > /tmp/go-module-license-paths \
    && test -s /tmp/go-module-license-paths \
    && tar -cf - -T /tmp/go-module-license-paths \
      | tar -xf - -C /tmp/go-licenses/go-modules \
    && cd /tmp/go-licenses/go-modules \
    && find . -type f -print | LC_ALL=C sort | xargs sha256sum \
      > /tmp/go-licenses/go-module-licenses.sha256

FROM upstream

USER 0
RUN apk add --upgrade --no-cache 'libcrypto3=3.5.8-r0' 'libssl3=3.5.8-r0' \
    && rm -f /lib/apk/db/lock /var/log/apk.log

COPY --from=builder /go/bin/dex /go/bin/docker-entrypoint /go/bin/gomplate /usr/local/bin/
COPY --from=builder /usr/local/src/dex/go.mod /usr/local/src/dex/go.sum /usr/local/src/dex/
COPY --from=builder /usr/local/src/dex/api/v2/go.mod /usr/local/src/dex/api/v2/go.sum /usr/local/src/dex/api/v2/

COPY --chown=1001:1001 web/templates/header.html web/templates/footer.html /srv/dex/web/templates/
COPY --chown=1001:1001 web/static/araihu-* web/static/appearance.js web/static/theme-default.js web/static/favicon.svg web/static/favicon-32.png web/static/icons.svg /srv/dex/web/static/
COPY --chown=0:0 web/static/theme-default.js /srv/dex/web/static/theme-default.template.js
COPY --chown=1001:1001 LICENSE NOTICE /usr/share/licenses/araihu-dex/
COPY --chown=1001:1001 licenses/Lato-OFL-1.1.txt licenses/musl-COPYRIGHT.txt /usr/share/licenses/araihu-dex/
COPY --from=builder --chown=1001:1001 /usr/local/src/gomplate/LICENSE /usr/share/licenses/araihu-dex/gomplate-MIT.txt
COPY --from=builder --chown=1001:1001 /tmp/go-licenses/ /usr/share/licenses/araihu-dex/
COPY --chown=1001:1001 .cache/sources/assets/NOTICE /usr/share/licenses/araihu-dex/assets-NOTICE
COPY --chown=1001:1001 .cache/sources/assets/licenses/Apache-2.0.txt .cache/sources/assets/licenses/heroicons-MIT.txt /usr/share/licenses/araihu-dex/
COPY --chown=1001:1001 entrypoint.sh /usr/local/bin/araihu-dex-entrypoint

ENV DEX_FRONTEND_DIR=/srv/dex/web
USER 1001:1001
ENTRYPOINT ["/usr/local/bin/araihu-dex-entrypoint"]
CMD ["dex", "serve", "/etc/dex/config.docker.yaml"]
